#!/usr/bin/env swift

// messages-bridge.swift
// A small CLI bridge for Claude Code to access Apple Messages (iMessage / SMS).
// Reads ~/Library/Messages/chat.db READ-ONLY; sends via AppleScript to Messages.app.
// Copyright © 2026 Tobias Stöger (tstoegi). Licensed under the MIT License.
// Usage:
//   messages-bridge chats [count]               - Recent conversations (default: 20)
//   messages-bridge unread [count]              - Unread incoming messages (default: 20)
//   messages-bridge list <chat|handle> [count]  - Recent messages of a conversation (default: 20)
//   messages-bridge search <query> [count]      - Search message bodies (default: 20)
//   messages-bridge read <chat|handle> [count]  - Like list, but full untruncated text (default: 10)
//   messages-bridge send <handle> <text>        - Send a message (iMessage, SMS fallback)
//
// Permissions: Full Disk Access for the terminal (to read chat.db) and
// Automation → Messages (to send).

import Contacts
import Foundation
import SQLite3

// MARK: - Database access

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
let dbPath = NSString(string: "~/Library/Messages/chat.db").expandingTildeInPath

/// Opens chat.db read-only. Exits with a human explanation rather than a crash
/// when macOS withholds the file — missing Full Disk Access is the usual cause.
func openDB() -> OpaquePointer {
    var db: OpaquePointer?
    let opened = sqlite3_open_v2("file:\(dbPath)?mode=ro", &db,
                                 SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
    guard opened == SQLITE_OK, let handle = db else {
        fputs("""
        Error: cannot open the Messages database at
          \(dbPath)
        The terminal running this tool most likely lacks Full Disk Access.
        Grant it in System Settings > Privacy & Security > Full Disk Access,
        then restart the terminal and try again.

        """, stderr)
        exit(1)
    }
    // Opening can succeed while reading is still denied — probe a real query.
    var probe: OpaquePointer?
    if sqlite3_prepare_v2(handle, "SELECT ROWID FROM message LIMIT 1", -1, &probe, nil) != SQLITE_OK {
        let detail = String(cString: sqlite3_errmsg(handle))
        fputs("""
        Error: the Messages database is not readable (\(detail)).
        Grant Full Disk Access to your terminal in System Settings >
        Privacy & Security > Full Disk Access, then restart the terminal.

        """, stderr)
        exit(1)
    }
    sqlite3_finalize(probe)
    return handle
}

/// Runs a query; `row` returns false to stop stepping early (used by search).
func query(_ db: OpaquePointer, _ sql: String, _ binds: [Any] = [],
           row: (OpaquePointer) -> Bool) {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
        fputs("SQL error: \(String(cString: sqlite3_errmsg(db)))\n", stderr)
        return
    }
    defer { sqlite3_finalize(s) }
    for (i, bind) in binds.enumerated() {
        let idx = Int32(i + 1)
        switch bind {
        case let v as String: sqlite3_bind_text(s, idx, v, -1, SQLITE_TRANSIENT)
        case let v as Int64: sqlite3_bind_int64(s, idx, v)
        case let v as Int: sqlite3_bind_int64(s, idx, Int64(v))
        default: sqlite3_bind_null(s, idx)
        }
    }
    while sqlite3_step(s) == SQLITE_ROW {
        if !row(s) { break }
    }
}

func colText(_ s: OpaquePointer, _ i: Int32) -> String? {
    guard let c = sqlite3_column_text(s, i) else { return nil }
    return String(cString: c)
}

func colInt(_ s: OpaquePointer, _ i: Int32) -> Int64 { sqlite3_column_int64(s, i) }

func colBlob(_ s: OpaquePointer, _ i: Int32) -> Data? {
    guard let p = sqlite3_column_blob(s, i) else { return nil }
    let n = Int(sqlite3_column_bytes(s, i))
    return n > 0 ? Data(bytes: p, count: n) : nil
}

// MARK: - Dates

let stampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f
}()

/// Message timestamps count from the Apple epoch (2001-01-01). Modern rows store
/// nanoseconds, older ones plain seconds — tell them apart by magnitude.
func appleDate(_ raw: Int64) -> Date? {
    guard raw != 0 else { return nil }
    let seconds = raw > 1_000_000_000_000 ? Double(raw) / 1_000_000_000 : Double(raw)
    return Date(timeIntervalSinceReferenceDate: seconds)
}

func stamp(_ raw: Int64) -> String {
    guard let d = appleDate(raw) else { return "—" }
    return stampFormatter.string(from: d)
}

// MARK: - Message body

func findBytes(_ haystack: [UInt8], _ needle: [UInt8]) -> Int? {
    guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
    for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
        return start
    }
    return nil
}

/// Apple frequently stores a message body ONLY as an archived NSAttributedString
/// (NSArchiver "typedstream") in `attributedBody`, leaving `text` NULL — about a
/// quarter of the rows here. Layout after the NSString class marker:
///   0x2B, then a length, then that many UTF-8 bytes.
/// The length is one byte when < 0x80, otherwise 0x81 + UInt16 LE (or 0x82 + UInt32 LE).
func decodeAttributedBody(_ data: Data) -> String? {
    let bytes = [UInt8](data)
    guard let anchor = findBytes(bytes, Array("NSString".utf8)),
          let plus = bytes[anchor...].firstIndex(of: 0x2B) else { return nil }

    var p = plus + 1
    guard p < bytes.count else { return nil }
    var len = Int(bytes[p]); p += 1

    if len == 0x81 {
        guard p + 1 < bytes.count else { return nil }
        len = Int(bytes[p]) | Int(bytes[p + 1]) << 8
        p += 2
    } else if len == 0x82 {
        guard p + 3 < bytes.count else { return nil }
        len = Int(bytes[p]) | Int(bytes[p + 1]) << 8 | Int(bytes[p + 2]) << 16 | Int(bytes[p + 3]) << 24
        p += 4
    } else if len >= 0x80 {
        return nil
    }
    guard len > 0, p + len <= bytes.count else { return nil }
    return String(bytes: bytes[p..<(p + len)], encoding: .utf8)
}

func bodyText(_ text: String?, _ blob: Data?) -> String {
    if let t = text, !t.isEmpty { return t }
    if let b = blob, let decoded = decodeAttributedBody(b), !decoded.isEmpty { return decoded }
    return ""
}

func oneLine(_ s: String, _ limit: Int) -> String {
    let flat = s.replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return flat.count <= limit ? flat : String(flat.prefix(limit)) + "…"
}

// MARK: - Contacts

var contactCache: [String: String]?

/// Phone numbers are written a dozen ways; compare on the last 9 digits.
func normPhone(_ s: String) -> String {
    let digits = s.filter(\.isNumber)
    return digits.count > 9 ? String(digits.suffix(9)) : digits
}

func contactIndex() -> [String: String] {
    if let cached = contactCache { return cached }
    var map: [String: String] = [:]
    let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
                CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
    do {
        try CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in
            let person = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let label = person.isEmpty ? c.organizationName : person
            guard !label.isEmpty else { return }
            for phone in c.phoneNumbers {
                let key = normPhone(phone.value.stringValue)
                if !key.isEmpty { map[key] = label }
            }
            for mail in c.emailAddresses {
                map[(mail.value as String).lowercased()] = label
            }
        }
    } catch {
        // No Contacts permission — fall back to raw handles, still useful.
    }
    contactCache = map
    return map
}

func displayName(for handle: String?) -> String {
    guard let h = handle, !h.isEmpty else { return "unknown" }
    let index = contactIndex()
    if h.contains("@") { return index[h.lowercased()] ?? h }
    return index[normPhone(h)] ?? h
}

func contactHandles(matchingName name: String) -> Set<String> {
    let keys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
    var keysWanted = Set<String>()
    guard let matches = try? CNContactStore().unifiedContacts(
        matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys) else { return [] }
    for c in matches {
        for p in c.phoneNumbers { keysWanted.insert(normPhone(p.value.stringValue)) }
        for m in c.emailAddresses { keysWanted.insert((m.value as String).lowercased()) }
    }
    return keysWanted
}

// MARK: - Chat resolution

/// Accepts a chat identifier, a raw handle, a group's display name, or a contact
/// name; returns the matching chat ROWIDs.
func resolveChats(_ db: OpaquePointer, _ arg: String) -> [Int64] {
    var ids: [Int64] = []
    query(db, """
        SELECT DISTINCT c.ROWID FROM chat c
        LEFT JOIN chat_handle_join chj ON chj.chat_id = c.ROWID
        LEFT JOIN handle h ON h.ROWID = chj.handle_id
        WHERE c.chat_identifier = ?1 COLLATE NOCASE
           OR c.display_name LIKE ?2
           OR h.id = ?1 COLLATE NOCASE
        """, [arg, "%\(arg)%"]) { s in ids.append(colInt(s, 0)); return true }
    if !ids.isEmpty { return ids }

    // Fall back to matching a contact by name, then that person's handles.
    let wanted = contactHandles(matchingName: arg)
    guard !wanted.isEmpty else { return [] }
    var handleIDs: [String] = []
    query(db, "SELECT id FROM handle", []) { s in
        if let id = colText(s, 0) {
            let key = id.contains("@") ? id.lowercased() : normPhone(id)
            if wanted.contains(key) { handleIDs.append(id) }
        }
        return true
    }
    guard !handleIDs.isEmpty else { return [] }
    let placeholders = handleIDs.map { _ in "?" }.joined(separator: ",")
    query(db, """
        SELECT DISTINCT c.ROWID FROM chat c
        JOIN chat_handle_join chj ON chj.chat_id = c.ROWID
        JOIN handle h ON h.ROWID = chj.handle_id
        WHERE h.id IN (\(placeholders))
        """, handleIDs) { s in ids.append(colInt(s, 0)); return true }
    return ids
}

func chatLabel(_ db: OpaquePointer, id: Int64, identifier: String, displayName name: String) -> String {
    if !name.isEmpty { return name }
    if !identifier.hasPrefix("chat") { return displayName(for: identifier) }
    // Group chat without a name: list its participants.
    var people: [String] = []
    query(db, """
        SELECT h.id FROM chat_handle_join chj
        JOIN handle h ON h.ROWID = chj.handle_id
        WHERE chj.chat_id = ?
        """, [id]) { s in
        if let h = colText(s, 0) { people.append(displayName(for: h)) }
        return true
    }
    return people.isEmpty ? identifier : "Group: " + people.prefix(4).joined(separator: ", ")
        + (people.count > 4 ? ", +\(people.count - 4)" : "")
}

// MARK: - Commands

func cmdChats(_ db: OpaquePointer, count: Int) {
    var rows: [(Int64, String, String, Int64)] = []
    query(db, """
        SELECT c.ROWID, c.chat_identifier, IFNULL(c.display_name, ''), MAX(m.date) AS last
        FROM chat c
        JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID
        JOIN message m ON m.ROWID = cmj.message_id
        GROUP BY c.ROWID ORDER BY last DESC LIMIT ?
        """, [count]) { s in
        rows.append((colInt(s, 0), colText(s, 1) ?? "", colText(s, 2) ?? "", colInt(s, 3)))
        return true
    }
    if rows.isEmpty { print("No conversations found."); return }

    for (i, r) in rows.enumerated() {
        let (id, identifier, name, last) = r
        var preview = "", fromMe = false, unread = 0
        query(db, """
            SELECT m.text, m.attributedBody, m.is_from_me FROM message m
            JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            WHERE cmj.chat_id = ? ORDER BY m.date DESC LIMIT 1
            """, [id]) { s in
            preview = bodyText(colText(s, 0), colBlob(s, 1))
            fromMe = colInt(s, 2) == 1
            return true
        }
        // item_type = 0 is a real message; other types are system rows (participant
        // changes, location shares) that carry no body and can never be "read".
        query(db, """
            SELECT COUNT(*) FROM message m
            JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            WHERE cmj.chat_id = ? AND m.is_from_me = 0 AND m.is_read = 0
              AND m.item_type = 0
            """, [id]) { s in unread = Int(colInt(s, 0)); return true }

        let label = chatLabel(db, id: id, identifier: identifier, displayName: name)
        let unreadMark = unread > 0 ? " [\(unread) unread]" : ""
        let who = fromMe ? "Me: " : ""
        print("\(i + 1). [\(stamp(last))] \(label) <\(identifier)>\(unreadMark) — \(who)\(oneLine(preview, 60))")
    }
}

func cmdUnread(_ db: OpaquePointer, count: Int) {
    var found = 0
    query(db, """
        SELECT m.date, h.id, m.text, m.attributedBody, IFNULL(c.chat_identifier, '')
        FROM message m
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE m.is_from_me = 0 AND m.is_read = 0 AND m.item_type = 0
        ORDER BY m.date DESC
        """, []) { s in
        // Many unread rows carry no body at all (tapbacks, system entries). Filter
        // first and count afterwards — a SQL LIMIT would spend itself on those and
        // report "none" while real messages sit further down.
        let body = bodyText(colText(s, 2), colBlob(s, 3))
        if body.isEmpty { return true }
        found += 1
        let handle = colText(s, 1)
        print("\(found). [\(stamp(colInt(s, 0)))] \(displayName(for: handle)) <\(handle ?? "—")> — \(oneLine(body, 70))")
        return found < count
    }
    if found == 0 { print("No unread messages.") }
}

func cmdList(_ db: OpaquePointer, target: String, count: Int, full: Bool) {
    let chats = resolveChats(db, target)
    guard !chats.isEmpty else {
        fputs("Error: no conversation found for '\(target)'.\nTry a phone number, an email address, a group name, or a contact name.\n", stderr)
        exit(1)
    }
    let placeholders = chats.map { _ in "?" }.joined(separator: ",")
    var binds: [Any] = chats.map { $0 as Any }
    binds.append(count)

    var rows: [(Int64, String?, Bool, String)] = []
    query(db, """
        SELECT m.date, h.id, m.is_from_me, m.text, m.attributedBody
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        WHERE cmj.chat_id IN (\(placeholders))
        ORDER BY m.date DESC LIMIT ?
        """, binds) { s in
        let body = bodyText(colText(s, 3), colBlob(s, 4))
        if !body.isEmpty {
            rows.append((colInt(s, 0), colText(s, 1), colInt(s, 2) == 1, body))
        }
        return true
    }
    if rows.isEmpty { print("No messages in this conversation."); return }

    // Query gives newest first; print chronologically so a thread reads naturally.
    for (i, r) in rows.reversed().enumerated() {
        let (date, handle, fromMe, body) = r
        let who = fromMe ? "Me" : displayName(for: handle)
        if full {
            print("\(i + 1). [\(stamp(date))] \(who):")
            print(body)
            print("")
        } else {
            print("\(i + 1). [\(stamp(date))] \(who): \(oneLine(body, 70))")
        }
    }
}

func cmdSearch(_ db: OpaquePointer, needle: String, count: Int) {
    // A quarter of the rows keep their body only in attributedBody, which SQL
    // cannot match — so walk newest-first and decode, stopping once we have enough.
    let lower = needle.lowercased()
    var found = 0
    query(db, """
        SELECT m.date, h.id, m.is_from_me, m.text, m.attributedBody
        FROM message m
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        ORDER BY m.date DESC
        """, []) { s in
        let body = bodyText(colText(s, 3), colBlob(s, 4))
        guard body.lowercased().contains(lower) else { return true }
        found += 1
        let handle = colText(s, 1)
        let who = colInt(s, 2) == 1 ? "Me" : displayName(for: handle)
        print("\(found). [\(stamp(colInt(s, 0)))] \(who) <\(handle ?? "—")> — \(oneLine(body, 70))")
        return found < count
    }
    if found == 0 { print("No messages matching '\(needle)'.") }
}

func asEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

func cmdSend(to rawHandle: String, text: String) {
    var handle = rawHandle
    // A bare name is only accepted when it maps to exactly one address.
    if !handle.contains("@"), handle.rangeOfCharacter(from: .decimalDigits) == nil {
        let keys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        var options: [String] = []
        if let matches = try? CNContactStore().unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: handle), keysToFetch: keys) {
            for c in matches {
                options.append(contentsOf: c.phoneNumbers.map { $0.value.stringValue })
                options.append(contentsOf: c.emailAddresses.map { $0.value as String })
            }
        }
        let unique = Array(Set(options))
        if unique.count == 1 {
            handle = unique[0]
            fputs("Resolved '\(rawHandle)' to \(handle)\n", stderr)
        } else if unique.isEmpty {
            fputs("Error: '\(rawHandle)' is not a phone number or email, and no contact of that name was found.\n", stderr)
            exit(1)
        } else {
            fputs("Error: '\(rawHandle)' is ambiguous — pass one of: \(unique.joined(separator: ", "))\n", stderr)
            exit(1)
        }
    }

    let script = """
    tell application "Messages"
        set theText to "\(asEscape(text))"
        set theHandle to "\(asEscape(handle))"
        try
            set svc to 1st service whose service type = iMessage
            send theText to buddy theHandle of svc
            return "iMessage"
        on error iMessageError
            try
                set smsSvc to 1st service whose service type = SMS
                send theText to buddy theHandle of smsSvc
                return "SMS"
            on error smsError
                error "iMessage: " & iMessageError & " / SMS: " & smsError
            end try
        end try
    end tell
    """
    var errorInfo: NSDictionary?
    guard let apple = NSAppleScript(source: script) else {
        fputs("Error: could not build the AppleScript.\n", stderr)
        exit(1)
    }
    let result = apple.executeAndReturnError(&errorInfo)
    if let error = errorInfo {
        let message = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
        fputs("""
        Error: sending to '\(handle)' failed.
        \(message)
        Check that the handle is reachable and that this terminal is allowed to
        control Messages (System Settings > Privacy & Security > Automation).

        """, stderr)
        exit(1)
    }
    let service = result.stringValue ?? "unknown service"
    print("Sent via \(service) to \(handle): \(oneLine(text, 60))")
}

// MARK: - Entry point

let args = CommandLine.arguments
guard args.count > 1 else {
    print("""
    Usage:
      messages-bridge chats [count]               List recent conversations (default: 20)
      messages-bridge unread [count]              List unread incoming messages (default: 20)
      messages-bridge list <chat|handle> [count]  List messages of a conversation (default: 20)
      messages-bridge search <query> [count]      Search message bodies (default: 20)
      messages-bridge read <chat|handle> [count]  Full untruncated messages (default: 10)
      messages-bridge send <handle> <text>        Send a message (iMessage, SMS fallback)
    """)
    exit(0)
}

switch args[1] {
case "chats":
    cmdChats(openDB(), count: args.count > 2 ? Int(args[2]) ?? 20 : 20)
case "unread":
    cmdUnread(openDB(), count: args.count > 2 ? Int(args[2]) ?? 20 : 20)
case "list", "read":
    guard args.count > 2 else {
        fputs("Usage: messages-bridge \(args[1]) <chat|handle> [count]\n", stderr)
        exit(1)
    }
    let isRead = args[1] == "read"
    let fallback = isRead ? 10 : 20
    cmdList(openDB(), target: args[2],
            count: args.count > 3 ? Int(args[3]) ?? fallback : fallback, full: isRead)
case "search":
    guard args.count > 2 else {
        fputs("Usage: messages-bridge search <query> [count]\n", stderr)
        exit(1)
    }
    cmdSearch(openDB(), needle: args[2], count: args.count > 3 ? Int(args[3]) ?? 20 : 20)
case "send":
    guard args.count > 3 else {
        fputs("Usage: messages-bridge send <handle> <text>\n", stderr)
        exit(1)
    }
    cmdSend(to: args[2], text: args[3...].joined(separator: " "))
default:
    fputs("Unknown command: \(args[1])\nRun messages-bridge without arguments for usage.\n", stderr)
    exit(1)
}
