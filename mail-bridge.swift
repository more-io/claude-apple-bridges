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
            set startIdx to msgCount - \(count - 1)
            if startIdx < 1 then set startIdx to 1
            repeat with i from msgCount to startIdx by -1
                set m to item i of msgs
                set isRead to read status of m
                set readMark to ""
                if isRead is false then set readMark to " [UNREAD]"
                set d to date received of m
                set mo to month of d as integer as string
                set da to day of d as string
                set displayIdx to (msgCount - i + 1) as text
                set entry to displayIdx & ". " & subject of m & readMark & " — " & sender of m & " (" & mo & "/" & da & ")"
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

func readMessage(index: Int, mailbox: String, account: String) {
    let accountClause = account.isEmpty
        ? "item 1 of accounts"
        : "account \"\(account)\""
    let result = runScript("""
        tell application "Mail"
            set acc to \(accountClause)
            set msgs to messages of mailbox "\(mailbox)" of acc
            set msgCount to count of msgs
            set reverseIdx to msgCount - \(index - 1)
            if reverseIdx < 1 or reverseIdx > msgCount then
                return "INDEX_OUT_OF_RANGE"
            end if
            set m to item reverseIdx of msgs
            set d to date received of m
            set dateStr to date string of d & " " & time string of d
            set msgContent to "From: " & sender of m & "\\nDate: " & dateStr & "\\nSubject: " & subject of m & "\\n---\\n" & content of m
            set read status of m to true
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

func sendMessage(to recipient: String, subject: String, body: String) {
    let result = runScript("""
        tell application "Mail"
            set newMsg to make new outgoing message with properties {subject:"\(subject)", content:"\(body)"}
            tell newMsg
                make new to recipient with properties {address:"\(recipient)"}
            end tell
            send newMsg
            return "OK"
        end tell
    """)
    if result?.stringValue == "OK" {
        print("Message sent to \(recipient).")
    } else {
        fputs("Failed to send message.\n", stderr)
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
            set reverseIdx to msgCount - \(index - 1)
            if reverseIdx < 1 or reverseIdx > msgCount then
                return "INDEX_OUT_OF_RANGE"
            end if
            delete item reverseIdx of msgs
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
    print("  mail-bridge read <index> [mailbox] [account]")
    print("  mail-bridge send <to> <subject> <body>")
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
        fputs("Usage: mail-bridge read <index> [mailbox] [account]\n", stderr)
        exit(1)
    }
    let mailbox = args.count >= 4 ? args[3] : defaultMailbox
    let account = args.count >= 5 ? args[4] : ""
    readMessage(index: index, mailbox: mailbox, account: account)

case "send":
    guard args.count >= 5 else {
        fputs("Usage: mail-bridge send <to> <subject> <body>\n", stderr)
        exit(1)
    }
    sendMessage(to: args[2], subject: args[3], body: args[4])

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
