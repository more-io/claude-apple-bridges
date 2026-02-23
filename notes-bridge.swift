#!/usr/bin/env swift

// notes-bridge.swift
// A small CLI bridge for Claude Code to access Apple Notes via NSAppleScript.
// Usage:
//   notes-bridge accounts                                      - List all accounts
//   notes-bridge folders [account]                             - List folders (default: iCloud)
//   notes-bridge list [folder] [account]                       - List notes in folder
//   notes-bridge search <query>                                - Search notes by title and content
//   notes-bridge read <title> [account]                        - Read note content (plain text)
//   notes-bridge add <folder> <title> <body> [account]         - Create new note
//   notes-bridge append <title> <text> [account]               - Append text to existing note

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
    // If it's a list, iterate via numberOfItems
    if desc.numberOfItems > 0 {
        var items: [String] = []
        for i in 1...desc.numberOfItems {
            if let item = desc.atIndex(i)?.stringValue {
                items.append(item)
            }
        }
        return items
    }
    // Single value
    if let value = desc.stringValue, !value.isEmpty {
        return [value]
    }
    return []
}

// MARK: - HTML Stripping

func stripHTML(_ html: String) -> String {
    var text = html
    // Block elements → newlines
    for tag in ["</p>", "<br>", "<br/>", "<br />", "</div>", "</li>"] {
        text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
    }
    // Strip all remaining HTML tags
    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    // Decode common HTML entities
    let entities: [(String, String)] = [
        ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"),
        ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")
    ]
    entities.forEach { text = text.replacingOccurrences(of: $0.0, with: $0.1) }
    // Collapse excessive newlines
    while text.contains("\n\n\n") {
        text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Commands

func listAccounts() {
    let result = runScript("""
        tell application "Notes"
            set out to {}
            repeat with acc in accounts
                set end of out to name of acc
            end repeat
            return out
        end tell
    """)
    descriptorToStrings(result).forEach { print($0) }
}

func listFolders(account: String) {
    let result = runScript("""
        tell application "Notes"
            set out to {}
            repeat with f in folders of account "\(account)"
                set end of out to name of f
            end repeat
            return out
        end tell
    """)
    let folders = descriptorToStrings(result)
    if folders.isEmpty {
        fputs("No folders found in account '\(account)'.\n", stderr)
        exit(1)
    }
    folders.forEach { print($0) }
}

func listNotes(folder: String, account: String) {
    let result = runScript("""
        tell application "Notes"
            set out to {}
            set targetFolder to folder "\(folder)" of account "\(account)"
            repeat with n in notes of targetFolder
                set d to modification date of n
                set dateStr to (year of d as string) & "-" ¬
                    & text -2 thru -1 of ("0" & (month of d as integer as string)) & "-" ¬
                    & text -2 thru -1 of ("0" & (day of d as string))
                set end of out to name of n & "  [" & dateStr & "]"
            end repeat
            return out
        end tell
    """)
    let notes = descriptorToStrings(result)
    if notes.isEmpty {
        print("No notes in '\(folder)'.")
    } else {
        notes.forEach { print($0) }
    }
}

func searchNotes(query: String) {
    let result = runScript("""
        tell application "Notes"
            set out to {}
            repeat with acc in accounts
                repeat with f in folders of acc
                    repeat with n in notes of f
                        set titleMatch to name of n contains "\(query)"
                        set bodyMatch to plaintext of n contains "\(query)"
                        if titleMatch or bodyMatch then
                            set end of out to name of n & "  [" & name of f & " / " & name of acc & "]"
                        end if
                    end repeat
                end repeat
            end repeat
            return out
        end tell
    """)
    let matches = descriptorToStrings(result)
    if matches.isEmpty {
        print("No notes matching '\(query)'.")
    } else {
        print("Found \(matches.count) note(s):")
        matches.forEach { print("  " + $0) }
    }
}

func readNote(title: String, account: String) {
    let result = runScript("""
        tell application "Notes"
            set matchNote to missing value
            repeat with acc in accounts
                if name of acc is "\(account)" or "\(account)" is "" then
                    repeat with f in folders of acc
                        repeat with n in notes of f
                            if name of n is "\(title)" then
                                set matchNote to n
                                exit repeat
                            end if
                        end repeat
                        if matchNote is not missing value then exit repeat
                    end repeat
                end if
                if matchNote is not missing value then exit repeat
            end repeat
            if matchNote is missing value then
                return "NOTE_NOT_FOUND"
            end if
            return plaintext of matchNote
        end tell
    """)
    guard let text = result?.stringValue else {
        fputs("Error reading note.\n", stderr)
        exit(1)
    }
    if text == "NOTE_NOT_FOUND" {
        fputs("Note '\(title)' not found.\n", stderr)
        exit(1)
    }
    print(text)
}

func addNote(folder: String, title: String, body: String, account: String) {
    let result = runScript("""
        tell application "Notes"
            set targetFolder to folder "\(folder)" of account "\(account)"
            make new note at targetFolder with properties {name:"\(title)", body:"\(body)"}
            return "OK"
        end tell
    """)
    if result?.stringValue == "OK" {
        print("Created note: \(title)")
    } else {
        fputs("Failed to create note.\n", stderr)
        exit(1)
    }
}

func appendToNote(title: String, text: String, account: String) {
    let result = runScript("""
        tell application "Notes"
            set matchNote to missing value
            repeat with acc in accounts
                if name of acc is "\(account)" or "\(account)" is "" then
                    repeat with f in folders of acc
                        repeat with n in notes of f
                            if name of n is "\(title)" then
                                set matchNote to n
                                exit repeat
                            end if
                        end repeat
                        if matchNote is not missing value then exit repeat
                    end repeat
                end if
                if matchNote is not missing value then exit repeat
            end repeat
            if matchNote is missing value then
                return "NOTE_NOT_FOUND"
            end if
            set body of matchNote to body of matchNote & "<br>\(text)"
            return "OK"
        end tell
    """)
    let status = result?.stringValue
    if status == "NOTE_NOT_FOUND" {
        fputs("Note '\(title)' not found.\n", stderr)
        exit(1)
    } else if status == "OK" {
        print("Appended to note: \(title)")
    } else {
        fputs("Failed to append to note.\n", stderr)
        exit(1)
    }
}

func deleteNote(title: String, account: String, force: Bool) {
    let result = runScript("""
        tell application "Notes"
            set matchNote to missing value
            repeat with acc in accounts
                if name of acc is "\(account)" or "\(account)" is "" then
                    repeat with f in folders of acc
                        repeat with n in notes of f
                            if name of n is "\(title)" then
                                set matchNote to n
                                exit repeat
                            end if
                        end repeat
                        if matchNote is not missing value then exit repeat
                    end repeat
                end if
                if matchNote is not missing value then exit repeat
            end repeat
            if matchNote is missing value then
                return "NOTE_NOT_FOUND"
            end if
            delete matchNote
            return "OK"
        end tell
    """)
    let status = result?.stringValue
    if status == "NOTE_NOT_FOUND" {
        fputs("Note '\(title)' not found.\n", stderr)
        exit(1)
    } else if status == "OK" {
        print("Deleted note: \(title)")
    } else {
        fputs("Failed to delete note.\n", stderr)
        exit(1)
    }
}

// MARK: - Main

let args = CommandLine.arguments

guard args.count >= 2 else {
    print("Usage:")
    print("  notes-bridge accounts")
    print("  notes-bridge folders [account]")
    print("  notes-bridge list [folder] [account]")
    print("  notes-bridge search <query>")
    print("  notes-bridge read <title> [account]")
    print("  notes-bridge add <folder> <title> <body> [account]")
    print("  notes-bridge append <title> <text> [account]")
    print("  notes-bridge delete <title> [--force] [account]")
    exit(0)
}

let command = args[1]
let defaultAccount = "iCloud"
let defaultFolder = "Notes"

switch command {

case "accounts":
    listAccounts()

case "folders":
    let account = args.count >= 3 ? args[2] : defaultAccount
    listFolders(account: account)

case "list":
    let folder = args.count >= 3 ? args[2] : defaultFolder
    let account = args.count >= 4 ? args[3] : defaultAccount
    listNotes(folder: folder, account: account)

case "search":
    guard args.count >= 3 else {
        fputs("Usage: notes-bridge search <query>\n", stderr)
        exit(1)
    }
    searchNotes(query: args[2])

case "read":
    guard args.count >= 3 else {
        fputs("Usage: notes-bridge read <title> [account]\n", stderr)
        exit(1)
    }
    let account = args.count >= 4 ? args[3] : ""
    readNote(title: args[2], account: account)

case "add":
    guard args.count >= 5 else {
        fputs("Usage: notes-bridge add <folder> <title> <body> [account]\n", stderr)
        exit(1)
    }
    let account = args.count >= 6 ? args[5] : defaultAccount
    addNote(folder: args[2], title: args[3], body: args[4], account: account)

case "append":
    guard args.count >= 4 else {
        fputs("Usage: notes-bridge append <title> <text> [account]\n", stderr)
        exit(1)
    }
    let account = args.count >= 5 ? args[4] : ""
    appendToNote(title: args[2], text: args[3], account: account)

case "delete":
    guard args.count >= 3 else {
        fputs("Usage: notes-bridge delete <title> [--force] [account]\n", stderr)
        exit(1)
    }
    let force = args.contains("--force")
    let account = args.filter { $0 != "--force" }.count >= 4 ? args.filter { $0 != "--force" }[3] : ""
    if !force {
        print("Dry-run: would delete '\(args[2])'. Use --force to actually delete.")
        exit(0)
    }
    deleteNote(title: args[2], account: account, force: force)

default:
    fputs("Unknown command: \(command)\n", stderr)
    exit(1)
}
