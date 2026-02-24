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
//   mail-bridge send <to> <subject> <body>             - Send a new email
//   mail-bridge delete <index> [mailbox] [account] [--force]  - Move message to Trash

import Foundation

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
        : "account \"\(account)\""
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
        : "account \"\(account)\""
    let result = runScript("""
        tell application "Mail"
            set out to {}
            set acc to \(accountClause)
            set msgs to messages of mailbox "\(mailbox)" of acc
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
        : "account \"\(account)\""
    let result = runScript("""
        tell application "Mail"
            set out to {}
            set acc to \(accountClause)
            set msgs to messages of mailbox "\(mailbox)" of acc
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

func searchMessages(query: String, account: String) {
    let accountClause = account.isEmpty
        ? "item 1 of accounts"
        : "account \"\(account)\""
    let result = runScript("""
        tell application "Mail"
            set out to {}
            set acc to \(accountClause)
            set msgs to messages of mailbox "INBOX" of acc
            set msgCount to count of msgs
            repeat with i from 1 to msgCount
                set m to item i of msgs
                set subjectMatch to subject of m contains "\(query)"
                set senderMatch to sender of m contains "\(query)"
                if subjectMatch or senderMatch then
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
    let matches = descriptorToStrings(result)
    if matches.isEmpty {
        print("No messages matching '\(query)'.")
    } else {
        print("Found \(matches.count) message(s):")
        matches.forEach { print("  " + $0) }
    }
}

func readMessage(index: Int, mailbox: String, account: String, markRead: Bool) {
    let accountClause = account.isEmpty
        ? "item 1 of accounts"
        : "account \"\(account)\""
    let markReadScript = markRead ? "set read status of m to true" : ""
    let result = runScript("""
        tell application "Mail"
            set acc to \(accountClause)
            set msgs to messages of mailbox "\(mailbox)" of acc
            set msgCount to count of msgs
            if \(index) < 1 or \(index) > msgCount then
                return "INDEX_OUT_OF_RANGE"
            end if
            set m to item \(index) of msgs
            set d to date received of m
            set dateStr to date string of d & " " & time string of d
            set msgContent to "From: " & sender of m & "\\nDate: " & dateStr & "\\nSubject: " & subject of m & "\\n---\\n" & content of m
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

func sendMessage(to recipient: String, subject: String, body: String, attachmentPath: String, fromEmail: String, force: Bool) {
    if !attachmentPath.isEmpty && !FileManager.default.fileExists(atPath: attachmentPath) {
        fputs("Attachment not found: \(attachmentPath)\n", stderr)
        exit(1)
    }
    let sender = fromEmail.isEmpty ? getDefaultSenderEmail() : fromEmail
    let senderProp = sender.isEmpty ? "" : ", sender:\"\(sender)\""
    let visibleProp = force ? "" : ", visible:true"
    var script = """
        tell application "Mail"
            set newMsg to make new outgoing message with properties {subject:"\(subject)", content:"\(body)"\(senderProp)\(visibleProp)}
            tell newMsg
                make new to recipient with properties {address:"\(recipient)"}
        """
    if !attachmentPath.isEmpty {
        script += "\n        make new attachment with properties {file name:POSIX file \"\(attachmentPath)\"}"
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
        : "account \"\(account)\""
    let result = runScript("""
        tell application "Mail"
            set acc to \(accountClause)
            set msgs to messages of mailbox "\(mailbox)" of acc
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
    print("  mail-bridge send <to> <subject> <body> [/path/to/attachment] [--from <email>] [--force]")
    print("  mail-bridge delete <index> [mailbox] [account] [--force]")
    exit(0)
}

let command = args[1]
let defaultMailbox = "INBOX"

switch command {

case "accounts":
    listAccounts()

case "mailboxes":
    let account = args.count >= 3 ? args[2] : ""
    listMailboxes(account: account)

case "list":
    let mailbox = args.count >= 3 ? args[2] : defaultMailbox
    let account = args.count >= 4 ? args[3] : ""
    let count = args.count >= 5 ? (Int(args[4]) ?? 20) : 20
    listMessages(mailbox: mailbox, account: account, count: count)

case "unread":
    let mailbox = args.count >= 3 ? args[2] : defaultMailbox
    let account = args.count >= 4 ? args[3] : ""
    listUnread(mailbox: mailbox, account: account)

case "search":
    guard args.count >= 3 else {
        fputs("Usage: mail-bridge search <query> [account]\n", stderr)
        exit(1)
    }
    let account = args.count >= 4 ? args[3] : ""
    searchMessages(query: args[2], account: account)

case "read":
    guard args.count >= 3, let index = Int(args[2]) else {
        fputs("Usage: mail-bridge read <index> [mailbox] [account] [--mark-read]\n", stderr)
        exit(1)
    }
    let markRead = args.contains("--mark-read")
    let readArgs = args.filter { $0 != "--mark-read" }
    let mailbox = readArgs.count >= 4 ? readArgs[3] : defaultMailbox
    let account = readArgs.count >= 5 ? readArgs[4] : ""
    readMessage(index: index, mailbox: mailbox, account: account, markRead: markRead)

case "send":
    guard args.count >= 5 else {
        fputs("Usage: mail-bridge send <to> <subject> <body> [/path/to/attachment] [--from <email>] [--force]\n", stderr)
        exit(1)
    }
    let force = args.contains("--force")
    var fromEmail = ""
    if let fromIdx = args.firstIndex(of: "--from"), fromIdx + 1 < args.count {
        fromEmail = args[fromIdx + 1]
    }
    let flagArgs = Set(["--force", "--from", fromEmail].filter { !$0.isEmpty })
    let positional = args.dropFirst(5).filter { !flagArgs.contains($0) }
    let attachmentPath = positional.first ?? ""
    sendMessage(to: args[2], subject: args[3], body: args[4], attachmentPath: attachmentPath, fromEmail: fromEmail, force: force)

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
