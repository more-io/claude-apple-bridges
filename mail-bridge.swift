#!/usr/bin/env swift

// mail-bridge.swift
// A small CLI bridge for Claude Code to access Apple Mail via NSAppleScript.
// Copyright © 2026 Tobias Stöger (tstoegi). Licensed under the MIT License.
// Usage:
//   mail-bridge accounts                               - List all accounts
//   mail-bridge mailboxes [account]                    - List mailboxes (default: first account)
//   mail-bridge list [mailbox] [account] [count]       - List recent messages (default: INBOX, 20)
//   mail-bridge unread [mailbox] [account]             - List unread messages (default: INBOX)
//   mail-bridge search <query> [account]               - Search subject/sender in INBOX
//   mail-bridge read <index> [mailbox] [account]       - Read message by index
//   mail-bridge send <to> <subject> <body>             - Send a new email (plain text)
//   mail-bridge send <to> <subject> --html-file <path>  - Send HTML email from file
//   mail-bridge delete <index> [mailbox] [account] [--force]  - Move message to Trash

import Foundation

// MARK: - String Helpers

// Escape strings for safe interpolation inside AppleScript double-quoted strings.
func escapeForAppleScript(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

// Normalize typographic quotes to ASCII equivalents for reliable matching.
func normalizeQuotes(in string: String) -> String {
    string
        .replacingOccurrences(of: "\u{2018}", with: "'")
        .replacingOccurrences(of: "\u{2019}", with: "'")
        .replacingOccurrences(of: "\u{201C}", with: "\"")
        .replacingOccurrences(of: "\u{201D}", with: "\"")
}

// MARK: - AppleScript Runner

func runScript(_ source: String) -> NSAppleEventDescriptor? {
    var errorInfo: NSDictionary?
    guard let script = NSAppleScript(source: source) else { return nil }
    let result = script.executeAndReturnError(&errorInfo)
    if let error = errorInfo {
        let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        fputs("AppleScript error: \(message)\n", stderr)
        return nil
    }
    return result
}

func descriptorToStrings(_ descriptor: NSAppleEventDescriptor?) -> [String] {
    guard let desc = descriptor else { return [] }
    if desc.numberOfItems > 0 {
        var items: [String] = []
        for i in 1...desc.numberOfItems {
            if let item = desc.atIndex(i)?.stringValue {
                items.append(item)
            }
        }
        return items
    }
    if let value = desc.stringValue, !value.isEmpty {
        return [value]
    }
    return []
}

// MARK: - Commands

func listAccounts() {
    let result = runScript("""
        tell application "Mail"
            set out to {}
            repeat with acc in accounts
                set end of out to name of acc
            end repeat
            return out
        end tell
    """)
    let accounts = descriptorToStrings(result)
    if accounts.isEmpty {
        print("No accounts found.")
    } else {
        accounts.forEach { print($0) }
    }
}

func listMailboxes(account: String) {
    let accountClause = account.isEmpty
        ? "item 1 of accounts"
        : "account \"\(escapeForAppleScript(account))\""
    let result = runScript("""
        tell application "Mail"
            set out to {}
            repeat with mb in mailboxes of \(accountClause)
                set end of out to name of mb
            end repeat
            return out
        end tell
    """)
    let mailboxes = descriptorToStrings(result)
    if mailboxes.isEmpty {
        fputs("No mailboxes found\(account.isEmpty ? "" : " for '\(account)'")\n", stderr)
        exit(1)
    }
    mailboxes.forEach { print($0) }
}

func listMessages(mailbox: String, account: String, count: Int) {
    let accountClause = account.isEmpty
        ? "item 1 of accounts"
        : "account \"\(escapeForAppleScript(account))\""
    let result = runScript("""
        tell application "Mail"
            set out to {}
            set acc to \(accountClause)
            set msgs to messages of mailbox "\(escapeForAppleScript(mailbox))" of acc
            set msgCount to count of msgs
            if msgCount is 0 then return out
            set endIdx to \(count)
            if endIdx > msgCount then set endIdx to msgCount
            repeat with i from 1 to endIdx
                set m to item i of msgs
                set isRead to read status of m
                set readMark to ""
                if isRead is false then set readMark to " [UNREAD]"
                set d to date received of m
                set mo to month of d as integer as string
                set da to day of d as string
                set entry to (i as text) & ". " & subject of m & readMark & " — " & sender of m & " (" & mo & "/" & da & ")"
                set end of out to entry
            end repeat
            return out
        end tell
    """)
    let messages = descriptorToStrings(result)
    if messages.isEmpty {
        print("No messages in '\(mailbox)'.")
    } else {
        messages.forEach { print($0) }
    }
}

func listUnread(mailbox: String, account: String) {
    let accountClause = account.isEmpty
        ? "item 1 of accounts"
        : "account \"\(escapeForAppleScript(account))\""
    let result = runScript("""
        tell application "Mail"
            set out to {}
            set acc to \(accountClause)
            set msgs to messages of mailbox "\(escapeForAppleScript(mailbox))" of acc
            set msgCount to count of msgs
            repeat with i from 1 to msgCount
                set m to item i of msgs
                if read status of m is false then
                    set d to date received of m
                    set mo to month of d as integer as string
                    set da to day of d as string
                    set entry to subject of m & " — " & sender of m & " (" & mo & "/" & da & ")"
                    set end of out to entry
                end if
            end repeat
            return out
        end tell
    """)
    let messages = descriptorToStrings(result)
    if messages.isEmpty {
        print("No unread messages in '\(mailbox)'.")
    } else {
        print("Unread in '\(mailbox)' (\(messages.count)):")
        messages.forEach { print("  " + $0) }
    }
}

func searchMessages(query: String, account: String, maxResults: Int) {
    let escapedQuery = escapeForAppleScript(query)
    let limit = maxResults > 0 ? maxResults : 50

    if account.isEmpty {
        // Search ALL accounts
        var allMatches: [String] = []
        for accName in accountNames {
            let escapedAcc = escapeForAppleScript(accName)
            let result = runScript("""
                tell application "Mail"
                    set out to {}
                    set acc to account "\(escapedAcc)"
                    set allMailboxes to {"INBOX"}
                    repeat with mbName in allMailboxes
                        try
                            set msgs to messages of mailbox (mbName as text) of acc
                            set msgCount to count of msgs
                            repeat with i from 1 to msgCount
                                set m to item i of msgs
                                set subjectMatch to subject of m contains "\(escapedQuery)"
                                set senderMatch to sender of m contains "\(escapedQuery)"
                                if subjectMatch or senderMatch then
                                    set d to date received of m
                                    set mo to month of d as integer as string
                                    set da to day of d as string
                                    set entry to "[" & name of acc & "] " & subject of m & " — " & sender of m & " (" & mo & "/" & da & ")"
                                    set end of out to entry
                                    if (count of out) >= \(limit) then return out
                                end if
                            end repeat
                        end try
                    end repeat
                    return out
                end tell
            """)
            allMatches.append(contentsOf: descriptorToStrings(result))
            if allMatches.count >= limit { break }
        }
        if allMatches.isEmpty {
            print("No messages matching '\(query)' across all accounts.")
        } else {
            print("Found \(allMatches.count) message(s):")
            allMatches.prefix(limit).forEach { print("  " + $0) }
        }
    } else {
        let result = runScript("""
            tell application "Mail"
                set out to {}
                set acc to account "\(escapeForAppleScript(account))"
                set msgs to messages of mailbox "INBOX" of acc
                set msgCount to count of msgs
                repeat with i from 1 to msgCount
                    set m to item i of msgs
                    set subjectMatch to subject of m contains "\(escapedQuery)"
                    set senderMatch to sender of m contains "\(escapedQuery)"
                    if subjectMatch or senderMatch then
                        set d to date received of m
                        set mo to month of d as integer as string
                        set da to day of d as string
                        set entry to subject of m & " — " & sender of m & " (" & mo & "/" & da & ")"
                        set end of out to entry
                        if (count of out) >= \(limit) then return out
                    end if
                end repeat
                return out
            end tell
        """)
        let matches = descriptorToStrings(result)
        if matches.isEmpty {
            print("No messages matching '\(query)'.")
        } else {
            print("Found \(matches.count) message(s):")
            matches.prefix(limit).forEach { print("  " + $0) }
        }
    }
}

func readMessage(index: Int, mailbox: String, account: String, markRead: Bool, raw: Bool) {
    let accountClause = account.isEmpty
        ? "item 1 of accounts"
        : "account \"\(escapeForAppleScript(account))\""
    let markReadScript = markRead ? "set read status of m to true" : ""
    let bodyProp = raw ? "source of m" : "content of m"
    let result = runScript("""
        tell application "Mail"
            set acc to \(accountClause)
            set msgs to messages of mailbox "\(escapeForAppleScript(mailbox))" of acc
            set msgCount to count of msgs
            if \(index) < 1 or \(index) > msgCount then
                return "INDEX_OUT_OF_RANGE"
            end if
            set m to item \(index) of msgs
            set d to date received of m
            set dateStr to date string of d & " " & time string of d
            set msgContent to "From: " & sender of m & "\\nDate: " & dateStr & "\\nSubject: " & subject of m & "\\n---\\n" & (\(bodyProp))
            \(markReadScript)
            return msgContent
        end tell
    """)
    guard let text = result?.stringValue else {
        fputs("Error reading message.\n", stderr)
        exit(1)
    }
    if text == "INDEX_OUT_OF_RANGE" {
        fputs("Message index \(index) is out of range.\n", stderr)
        exit(1)
    }
    print(text)
}

func getDefaultSenderEmail() -> String {
    let result = runScript("""
        tell application "Mail"
            set acc to item 1 of accounts
            set addrs to email addresses of acc
            if (count of addrs) > 0 then
                return item 1 of addrs
            end if
            return ""
        end tell
    """)
    return result?.stringValue ?? ""
}

func sendMessage(to recipient: String, subject: String, body: String, attachmentPath: String, fromEmail: String, force: Bool, htmlFilePath: String) {
    if !attachmentPath.isEmpty && !FileManager.default.fileExists(atPath: attachmentPath) {
        fputs("Attachment not found: \(attachmentPath)\n", stderr)
        exit(1)
    }
    if !htmlFilePath.isEmpty && !FileManager.default.fileExists(atPath: htmlFilePath) {
        fputs("HTML file not found: \(htmlFilePath)\n", stderr)
        exit(1)
    }
    let sender = fromEmail.isEmpty ? getDefaultSenderEmail() : fromEmail
    let senderProp = sender.isEmpty ? "" : ", sender:\"\(escapeForAppleScript(sender))\""
    let visibleProp = force ? "" : ", visible:true"

    // When using --html-file, read HTML from file inside AppleScript to avoid escaping issues.
    // The content property is set to empty string; html content overrides it.
    let contentValue = htmlFilePath.isEmpty ? escapeForAppleScript(body) : ""
    var script = """
        tell application "Mail"
            set newMsg to make new outgoing message with properties {subject:"\(escapeForAppleScript(subject))", content:"\(contentValue)"\(senderProp)\(visibleProp)}
            tell newMsg
                make new to recipient with properties {address:"\(escapeForAppleScript(recipient))"}
        """
    if !htmlFilePath.isEmpty {
        script += "\n        set html content of newMsg to (do shell script \"cat \" & quoted form of \"\(escapeForAppleScript(htmlFilePath))\")"
    }
    if !attachmentPath.isEmpty {
        script += "\n        make new attachment with properties {file name:POSIX file \"\(escapeForAppleScript(attachmentPath))\"}"
    }
    if force {
        script += """

                end tell
                send newMsg
                return "SENT"
            end tell
        """
    } else {
        script += """

                end tell
            end tell
            activate
            return "OPENED"
        """
    }
    let result = runScript(script)
    let status = result?.stringValue
    if status == "SENT" {
        let sentAttach = attachmentPath.isEmpty ? "" : ", with attachment"
        let sentFrom = sender.isEmpty ? "" : " from \(sender)"
        print("Message sent to \(recipient)\(sentFrom)\(sentAttach).")
    } else if status == "OPENED" {
        let openAttach = attachmentPath.isEmpty ? "" : " with attachment"
        print("Compose window opened\(openAttach) — review and send manually in Mail.app.")
    } else {
        fputs("Failed to compose message.\n", stderr)
        exit(1)
    }
}

func deleteMessage(index: Int, mailbox: String, account: String, force: Bool) {
    if !force {
        print("Dry-run: would move message #\(index) in '\(mailbox)' to Trash. Use --force to actually delete.")
        exit(0)
    }
    let accountClause = account.isEmpty
        ? "item 1 of accounts"
        : "account \"\(escapeForAppleScript(account))\""
    let result = runScript("""
        tell application "Mail"
            set acc to \(accountClause)
            set msgs to messages of mailbox "\(escapeForAppleScript(mailbox))" of acc
            set msgCount to count of msgs
            if \(index) < 1 or \(index) > msgCount then
                return "INDEX_OUT_OF_RANGE"
            end if
            delete item \(index) of msgs
            return "OK"
        end tell
    """)
    let status = result?.stringValue
    if status == "INDEX_OUT_OF_RANGE" {
        fputs("Message index \(index) is out of range.\n", stderr)
        exit(1)
    } else if status == "OK" {
        print("Moved message #\(index) to Trash.")
    } else {
        fputs("Failed to delete message.\n", stderr)
        exit(1)
    }
}

// MARK: - Main

let args = CommandLine.arguments

guard args.count >= 2 else {
    print("Usage:")
    print("  mail-bridge accounts")
    print("  mail-bridge mailboxes [account]")
    print("  mail-bridge list [mailbox] [account] [count]")
    print("  mail-bridge unread [mailbox] [account]")
    print("  mail-bridge search <query> [account]")
    print("  mail-bridge read <index> [mailbox] [account] [--mark-read]")
    print("  mail-bridge send <to> <subject> <body> [/path/to/attachment] [--from <email>] [--html-file <path>] [--force]")
    print("  mail-bridge delete <index> [mailbox] [account] [--force]")
    exit(0)
}

let command = args[1]
let defaultMailbox = "INBOX"

// Get all account names for smart argument detection
func getAccountNames() -> [String] {
    let result = runScript("""
        tell application "Mail"
            set out to {}
            repeat with acc in accounts
                set end of out to name of acc
            end repeat
            return out
        end tell
    """)
    return descriptorToStrings(result)
}

let accountNames = getAccountNames()

// Check if a string is an account name (not a mailbox)
func isAccountName(_ name: String) -> Bool {
    let normalized = normalizeQuotes(in: name)
    return accountNames.contains(where: { normalizeQuotes(in: $0) == normalized })
}

switch command {

case "accounts":
    listAccounts()

case "mailboxes":
    let account = args.count >= 3 ? args[2] : ""
    listMailboxes(account: account)

case "list":
    var mailbox = defaultMailbox
    var account = ""
    var count = 20
    if args.count >= 3 {
        if let num = Int(args[2]) {
            // list <count>
            count = num
        } else if isAccountName(args[2]) {
            // list <account> [count]
            account = args[2]
            count = args.count >= 4 ? (Int(args[3]) ?? 20) : 20
        } else {
            // list <mailbox> [count | account] [count]
            mailbox = args[2]
            if args.count >= 4 {
                if let num = Int(args[3]) {
                    count = num
                } else if isAccountName(args[3]) {
                    account = args[3]
                    count = args.count >= 5 ? (Int(args[4]) ?? 20) : 20
                }
            }
        }
    }
    listMessages(mailbox: mailbox, account: account, count: count)

case "unread":
    var mailbox = defaultMailbox
    var account = ""
    if args.count >= 3 {
        if isAccountName(args[2]) {
            account = args[2]
        } else {
            mailbox = args[2]
            account = args.count >= 4 ? args[3] : ""
        }
    }
    listUnread(mailbox: mailbox, account: account)

case "search":
    guard args.count >= 3 else {
        fputs("Usage: mail-bridge search <query> [max_results] [account]\n", stderr)
        exit(1)
    }
    var searchAccount = ""
    var searchMax = 50
    // args after query: could be a number (max results), an account name, or both
    if args.count >= 4 {
        if let num = Int(args[3]) {
            searchMax = num
            searchAccount = args.count >= 5 ? args[4] : ""
        } else if isAccountName(args[3]) {
            searchAccount = args[3]
        }
    }
    searchMessages(query: args[2], account: searchAccount, maxResults: searchMax)

case "read":
    guard args.count >= 3, let index = Int(args[2]) else {
        fputs("Usage: mail-bridge read <index> [mailbox] [account] [--mark-read] [--raw]\n", stderr)
        exit(1)
    }
    let markRead = args.contains("--mark-read")
    let raw = args.contains("--raw")
    let readArgs = args.filter { $0 != "--mark-read" && $0 != "--raw" }
    let mailbox = readArgs.count >= 4 ? readArgs[3] : defaultMailbox
    let account = readArgs.count >= 5 ? readArgs[4] : ""
    readMessage(index: index, mailbox: mailbox, account: account, markRead: markRead, raw: raw)

case "send":
    let force = args.contains("--force")
    var fromEmail = ""
    if let fromIdx = args.firstIndex(of: "--from"), fromIdx + 1 < args.count {
        fromEmail = args[fromIdx + 1]
    }
    var htmlFilePath = ""
    if let htmlIdx = args.firstIndex(of: "--html-file"), htmlIdx + 1 < args.count {
        htmlFilePath = args[htmlIdx + 1]
    }
    // With --html-file, body is optional (only to/subject required)
    let minArgs = htmlFilePath.isEmpty ? 5 : 4
    guard args.count >= minArgs else {
        fputs("Usage: mail-bridge send <to> <subject> [body] [/path/to/attachment] [--from <email>] [--html-file <path>] [--force]\n", stderr)
        exit(1)
    }
    let body = args.count >= 5 ? args[4] : ""
    let flagArgs = Set(["--force", "--from", fromEmail, "--html-file", htmlFilePath].filter { !$0.isEmpty })
    let positional = args.dropFirst(min(5, args.count)).filter { !flagArgs.contains($0) }
    let attachmentPath = positional.first ?? ""
    sendMessage(to: args[2], subject: args[3], body: body, attachmentPath: attachmentPath, fromEmail: fromEmail, force: force, htmlFilePath: htmlFilePath)

case "delete":
    guard args.count >= 3, let index = Int(args[2]) else {
        fputs("Usage: mail-bridge delete <index> [mailbox] [account] [--force]\n", stderr)
        exit(1)
    }
    let force = args.contains("--force")
    let filteredArgs = args.filter { $0 != "--force" }
    let mailbox = filteredArgs.count >= 4 ? filteredArgs[3] : defaultMailbox
    let account = filteredArgs.count >= 5 ? filteredArgs[4] : ""
    deleteMessage(index: index, mailbox: mailbox, account: account, force: force)

default:
    fputs("Unknown command: \(command)\n", stderr)
    exit(1)
}
