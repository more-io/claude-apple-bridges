#!/usr/bin/env swift

// tmux-bridge.swift
// A small CLI bridge for Claude Code to read tmux session contents.
// Copyright © 2026 Tobias Stöger (tstoegi). Licensed under the MIT License.
// Usage:
//   tmux-bridge sessions                          - List all running sessions
//   tmux-bridge windows [session]                 - List windows in a session
//   tmux-bridge panes [session]                   - List all panes in a session
//   tmux-bridge read <session:window.pane>         - Read pane content
//   tmux-bridge snapshot [session]                - Read all panes (for end-of-day summary)

import Foundation

// MARK: - Shell Runner

func shell(_ args: [String]) -> (output: String, exit: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try? process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines) ?? ""
    return (output, process.terminationStatus)
}

func tmux(_ args: [String]) -> String {
    let result = shell(["tmux"] + args)
    return result.output
}

func tmuxLines(_ args: [String]) -> [String] {
    let output = tmux(args)
    guard !output.isEmpty else { return [] }
    return output.components(separatedBy: "\n").filter { !$0.isEmpty }
}

// MARK: - Commands

func listSessions() {
    let lines = tmuxLines(["list-sessions", "-F",
        "#S  windows:#{session_windows}  created:#{session_created_string}  #{?session_attached,(attached),}"])
    if lines.isEmpty {
        print("No tmux sessions running.")
    } else {
        print("Sessions (\(lines.count)):")
        lines.forEach { print("  " + $0) }
    }
}

func listWindows(session: String) {
    let target = session.isEmpty ? "" : "-t \(session)"
    let args = ["list-windows"] + (session.isEmpty ? [] : ["-t", session]) + ["-F",
        "#{window_index}: #{window_name}  [#{window_width}x#{window_height}]  #{window_panes} pane(s)#{?window_active, (active),}"]
    let lines = tmuxLines(args)
    if lines.isEmpty {
        fputs("No windows found\(session.isEmpty ? "" : " in session '\(session)'")\n", stderr)
        exit(1)
    }
    let label = session.isEmpty ? "current session" : "session '\(session)'"
    print("Windows in \(label):")
    lines.forEach { print("  " + $0) }
    _ = target
}

func listPanes(session: String) {
    let args = ["list-panes"] + (session.isEmpty ? ["-a"] : ["-t", session, "-a"]) + ["-F",
        "#{session_name}:#{window_index}.#{pane_index}  [#{pane_width}x#{pane_height}]  #{pane_current_command}  #{pane_current_path}"]
    let lines = tmuxLines(args)
    if lines.isEmpty {
        fputs("No panes found\(session.isEmpty ? "" : " in session '\(session)'")\n", stderr)
        exit(1)
    }
    let paneLabel = session.isEmpty ? "Panes" : "Panes in '\(session)'"
    print("\(paneLabel) (\(lines.count)):")
    lines.forEach { print("  " + $0) }
}

func readPane(target: String, lines: Int) {
    // target format: session:window.pane  e.g. "main:0.0" or just "main"
    let result = shell(["tmux", "capture-pane", "-t", target, "-p", "-S", "-\(lines)"])
    if result.exit != 0 {
        fputs("Pane '\(target)' not found. Use 'tmux-bridge panes' to list available targets.\n", stderr)
        exit(1)
    }
    let content = result.output
    if content.isEmpty {
        print("(empty)")
    } else {
        print(content)
    }
}

func snapshot(session: String, lines: Int) {
    // Get all panes
    let args = ["list-panes"] + (session.isEmpty ? ["-a"] : ["-t", session]) + ["-F",
        "#{session_name}:#{window_index}.#{pane_index}\t#{window_name}\t#{pane_current_command}\t#{pane_current_path}"]
    let paneLines = tmuxLines(args)

    if paneLines.isEmpty {
        fputs("No panes found\(session.isEmpty ? "" : " in '\(session)'")\n", stderr)
        exit(1)
    }

    let label = session.isEmpty ? "all sessions" : "session '\(session)'"
    print("=== tmux snapshot: \(label) ===")
    print("Captured: \(Date())")
    print("")

    for paneLine in paneLines {
        let parts = paneLine.components(separatedBy: "\t")
        guard parts.count >= 4 else { continue }
        let target = parts[0]
        let windowName = parts[1]
        let command = parts[2]
        let path = parts[3]

        print("─────────────────────────────────────")
        print("Pane: \(target)  [\(windowName)] \(command) @ \(path)")
        print("─────────────────────────────────────")

        let result = shell(["tmux", "capture-pane", "-t", target, "-p", "-S", "-\(lines)"])
        let content = result.output
        if content.isEmpty {
            print("(empty)")
        } else {
            print(content)
        }
        print("")
    }
}

// MARK: - Main

let args = CommandLine.arguments

guard args.count >= 2 else {
    print("Usage:")
    print("  tmux-bridge sessions                         List all running sessions")
    print("  tmux-bridge windows [session]                List windows in session")
    print("  tmux-bridge panes [session]                  List all panes")
    print("  tmux-bridge read <target> [lines]            Read pane (e.g. main:0.0, default: 1000 lines)")
    print("  tmux-bridge snapshot [session] [lines]       Full snapshot of all panes (default: 5000 lines)")
    exit(0)
}

let command = args[1]

switch command {

case "sessions":
    listSessions()

case "windows":
    let session = args.count >= 3 ? args[2] : ""
    listWindows(session: session)

case "panes":
    let session = args.count >= 3 ? args[2] : ""
    listPanes(session: session)

case "read":
    guard args.count >= 3 else {
        fputs("Usage: tmux-bridge read <target> [lines]\n", stderr)
        exit(1)
    }
    let lines = args.count >= 4 ? (Int(args[3]) ?? 1000) : 1000
    readPane(target: args[2], lines: lines)

case "snapshot":
    let session = args.count >= 3 && Int(args[2]) == nil ? args[2] : ""
    let lines = args.count >= 3 && Int(args[2]) != nil ? (Int(args[2]) ?? 5000) :
                args.count >= 4 ? (Int(args[3]) ?? 5000) : 5000
    snapshot(session: session, lines: lines)

default:
    fputs("Unknown command: \(command)\n", stderr)
    exit(1)
}
