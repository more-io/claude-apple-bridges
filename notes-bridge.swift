#!/usr/bin/env swift

// notes-bridge.swift
// A small CLI bridge for Claude Code to access Apple Notes via NSAppleScript.
// Usage:
//   notes-bridge accounts                                      - List all accounts
//   notes-bridge folders [account]                             - List folders (default: iCloud)
//   notes-bridge list [folder] [account]                       - List notes in folder
//   notes-bridge search <query>                                - Search notes by title and content
//   notes-bridge read <title> [--html] [account]               - Read note content (plain text, or raw HTML)
//   notes-bridge add <folder> <title> <body|--file path> [account]         - Create new note
//   notes-bridge append <title> <text|--file path> [account]               - Append text to existing note
//   notes-bridge update <title> <body|--file path> [account]               - Replace a note's content (title kept)
//   notes-bridge move <title> <folder> [account]               - Move a note to another folder
//   notes-bridge delete <title> [--force] [account]            - Delete a note (dry-run without --force)

import Foundation

// MARK: - String Helpers

func escapeForAppleScript(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

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

// MARK: - Note lookup

/// AppleScript that sets `matchNote` to the first note whose name is `title` (in `account`, or any
/// account when empty), or to `missing value`. Callers return "NOTE_NOT_FOUND" when it is missing.
func findNoteScript(title: String, account: String) -> String {
    """
    set matchNote to missing value
    set matchFolder to ""
    repeat with acc in accounts
        if name of acc is "\(escapeForAppleScript(account))" or "\(escapeForAppleScript(account))" is "" then
            repeat with f in folders of acc
                -- `whose` gives references that keep resolving; a reference taken from a
                -- `repeat with n in notes of f` loop ("item 1 of every note") can fail later.
                set found to (notes of f whose name is "\(escapeForAppleScript(title))")
                if (count of found) > 0 then
                    set matchNote to item 1 of found
                    set matchFolder to name of f
                    exit repeat
                end if
            end repeat
        end if
        if matchNote is not missing value then exit repeat
    end repeat
    if matchNote is missing value then return "NOTE_NOT_FOUND"
    """
}

/// Notes derives a note's title from the first line of its body and ignores the `name` property
/// when a body is given. So a body that does not start with the title would create a note under a
/// different name, which `read`, `append`, `update` and `delete` then can't find by title.
func bodyWithTitle(_ title: String, _ body: String) -> String {
    let t = title.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    return "<div><h1>\(t)</h1></div>" + body
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
            repeat with f in folders of account "\(escapeForAppleScript(account))"
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
            set targetFolder to folder "\(escapeForAppleScript(folder))" of account "\(escapeForAppleScript(account))"
            repeat with n in notes of targetFolder
                set d to modification date of n
                set dateStr to (year of d as string) & "-" ¬
                    & text -2 thru -1 of ("0" & (month of d as integer as string)) & "-" ¬
                    & text -2 thru -1 of ("0" & (day of d as string)) & " " ¬
                    & text -2 thru -1 of ("0" & (hours of d as string)) & ":" ¬
                    & text -2 thru -1 of ("0" & (minutes of d as string)) & ":" ¬
                    & text -2 thru -1 of ("0" & (seconds of d as string))
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
                        set titleMatch to name of n contains "\(escapeForAppleScript(query))"
                        set bodyMatch to plaintext of n contains "\(escapeForAppleScript(query))"
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

func readNote(title: String, account: String, html: Bool) {
    let result = runScript("""
        tell application "Notes"
            \(findNoteScript(title: title, account: account))
            return \(html ? "body" : "plaintext") of matchNote
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
            set targetFolder to folder "\(escapeForAppleScript(folder))" of account "\(escapeForAppleScript(account))"
            make new note at targetFolder with properties {body:"\(escapeForAppleScript(bodyWithTitle(title, body)))"}
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
            \(findNoteScript(title: title, account: account))
            set body of matchNote to body of matchNote & "<br>\(escapeForAppleScript(text))"
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

func updateNote(title: String, body: String, account: String) {
    let result = runScript("""
        tell application "Notes"
            \(findNoteScript(title: title, account: account))
            set body of matchNote to "\(escapeForAppleScript(bodyWithTitle(title, body)))"
            return "OK"
        end tell
    """)
    let status = result?.stringValue
    if status == "NOTE_NOT_FOUND" {
        fputs("Note '\(title)' not found.\n", stderr)
        exit(1)
    } else if status == "OK" {
        print("Updated note: \(title)")
    } else {
        fputs("Failed to update note.\n", stderr)
        exit(1)
    }
}

func moveNote(title: String, folder: String, account: String) {
    let result = runScript("""
        tell application "Notes"
            \(findNoteScript(title: title, account: account))
            set targetAcc to account of container of matchNote
            move matchNote to folder "\(escapeForAppleScript(folder))" of targetAcc
            return "OK"
        end tell
    """)
    let status = result?.stringValue
    if status == "NOTE_NOT_FOUND" {
        fputs("Note '\(title)' not found.\n", stderr)
        exit(1)
    } else if status == "OK" {
        print("Moved note '\(title)' to \(folder)")
    } else {
        fputs("Failed to move note.\n", stderr)
        exit(1)
    }
}

func deleteNote(title: String, account: String, force: Bool) {
    let result = runScript("""
        tell application "Notes"
            \(findNoteScript(title: title, account: account))
            set noteId to id of matchNote
            set origFolder to matchFolder
            -- Notes may raise an error after the delete has already gone through (the reference
            -- to the note stops resolving), so the error is ignored and the outcome is checked.
            try
                delete matchNote
            end try
            try
                set nowFolder to name of container of note id noteId
                if nowFolder is origFolder then return "NOT_DELETED"
            end try
            return "OK"
        end tell
    """)
    let status = result?.stringValue
    if status == "NOTE_NOT_FOUND" {
        fputs("Note '\(title)' not found.\n", stderr)
        exit(1)
    } else if status == "OK" {
        print("Deleted note: \(title)")
    } else if status == "NOT_DELETED" {
        fputs("Note '\(title)' is still in its folder; delete did not take effect.\n", stderr)
        exit(1)
    } else {
        fputs("Failed to delete note.\n", stderr)
        exit(1)
    }
}

// MARK: - Main

/// `--file <path>` in place of the body/text argument of add, append and update: the file's contents
/// take the place of the two arguments. A large note can then be handed over as a path instead of
/// being passed through the caller's context. Errors out before any AppleScript runs.
func resolveFileArgument(_ argv: [String]) -> [String] {
    guard argv.count >= 2, ["add", "append", "update"].contains(argv[1]),
          let i = argv.firstIndex(of: "--file") else { return argv }
    guard i + 1 < argv.count else {
        fputs("--file needs a path.\n", stderr)
        exit(1)
    }
    let path = (argv[i + 1] as NSString).expandingTildeInPath
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue,
          let data = FileManager.default.contents(atPath: path),
          let text = String(data: data, encoding: .utf8) else {
        fputs("Cannot read '\(path)' as a UTF-8 text file.\n", stderr)
        exit(1)
    }
    var out = argv
    out.replaceSubrange(i...(i + 1), with: [text])
    return out
}

let args = resolveFileArgument(CommandLine.arguments)

guard args.count >= 2 else {
    print("Usage:")
    print("  notes-bridge accounts")
    print("  notes-bridge folders [account]")
    print("  notes-bridge list [folder] [account]")
    print("  notes-bridge search <query>")
    print("  notes-bridge read <title> [--html] [account]")
    print("  notes-bridge add <folder> <title> <body|--file path> [account]")
    print("  notes-bridge append <title> <text|--file path> [account]")
    print("  notes-bridge update <title> <body|--file path> [account]")
    print("  notes-bridge move <title> <folder> [account]")
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
        fputs("Usage: notes-bridge read <title> [--html] [account]\n", stderr)
        exit(1)
    }
    let html = args.contains("--html")
    let rest = args.filter { $0 != "--html" }
    let account = rest.count >= 4 ? rest[3] : ""
    readNote(title: rest[2], account: account, html: html)

case "add":
    guard args.count >= 5 else {
        fputs("Usage: notes-bridge add <folder> <title> <body|--file path> [account]\n", stderr)
        exit(1)
    }
    let account = args.count >= 6 ? args[5] : defaultAccount
    addNote(folder: args[2], title: args[3], body: args[4], account: account)

case "append":
    guard args.count >= 4 else {
        fputs("Usage: notes-bridge append <title> <text|--file path> [account]\n", stderr)
        exit(1)
    }
    let account = args.count >= 5 ? args[4] : ""
    appendToNote(title: args[2], text: args[3], account: account)

case "update":
    guard args.count >= 4 else {
        fputs("Usage: notes-bridge update <title> <body|--file path> [account]\n", stderr)
        exit(1)
    }
    let account = args.count >= 5 ? args[4] : ""
    updateNote(title: args[2], body: args[3], account: account)

case "move":
    guard args.count >= 4 else {
        fputs("Usage: notes-bridge move <title> <folder> [account]\n", stderr)
        exit(1)
    }
    let account = args.count >= 5 ? args[4] : ""
    moveNote(title: args[2], folder: args[3], account: account)

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
