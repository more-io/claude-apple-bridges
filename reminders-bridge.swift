#!/usr/bin/env swift

// reminders-bridge.swift
// Copyright © 2026 Tobias Stöger (tstoegi). Licensed under the MIT License.
// A small CLI bridge for Claude Code to access Apple Reminders via EventKit.
// Usage:
//   reminders-bridge lists                              - List all reminder lists
//   reminders-bridge create-list <listName>             - Create a new list
//   reminders-bridge items <listName>                   - List all reminders in a list
//   reminders-bridge incomplete <listName>              - Show incomplete reminders in a list
//   reminders-bridge today                              - Show reminders due today (all lists)
//   reminders-bridge overdue                            - Show overdue reminders (all lists)
//   reminders-bridge search <query>                     - Search reminders by title/notes (all lists)
//   reminders-bridge add <listName> <title> [notes]     - Add a new reminder
//   reminders-bridge set-due <listName> <title> <datetime> - Set due date (YYYY-MM-DD HH:mm)
//   reminders-bridge set-notes <listName> <title> <notes>  - Set or update notes
//   reminders-bridge complete <listName> <title>        - Mark a reminder as complete
//   reminders-bridge delete <listName> <title>          - Delete a reminder

import EventKit
import Foundation

let store = EKEventStore()

func requestAccess() async -> Bool {
    do {
        return try await store.requestFullAccessToReminders()
    } catch {
        fputs("Error requesting access: \(error.localizedDescription)\n", stderr)
        return false
    }
}

// MARK: - Formatting

func formatReminder(_ reminder: EKReminder) {
    let status = reminder.isCompleted ? "[x]" : "[ ]"
    let dueStr: String
    if let due = reminder.dueDateComponents, let date = Calendar.current.date(from: due) {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        dueStr = " (due: \(formatter.string(from: date)))"
    } else {
        dueStr = ""
    }
    let priority: String
    switch reminder.priority {
    case 1...4: priority = " !!"
    case 5:     priority = " !"
    default:    priority = ""
    }
    let recurrenceStr: String
    if let rules = reminder.recurrenceRules, let rule = rules.first {
        let freq: String
        switch rule.frequency {
        case .daily:   freq = "daily"
        case .weekly:  freq = "weekly"
        case .monthly: freq = "monthly"
        case .yearly:  freq = "yearly"
        @unknown default: freq = "unknown"
        }
        let interval = rule.interval > 1 ? " (every \(rule.interval))" : ""
        recurrenceStr = " [repeats: \(freq)\(interval)]"
    } else {
        recurrenceStr = ""
    }
    let listStr = " [\(reminder.calendar.title)]"
    let notesStr = (reminder.notes != nil && !reminder.notes!.isEmpty) ? "\n     Notes: \(reminder.notes!)" : ""
    print("\(status) \(reminder.title ?? "(no title)")\(priority)\(dueStr)\(recurrenceStr)\(listStr)\(notesStr)")
}

// MARK: - Fetch Helpers

func fetchAll(from calendars: [EKCalendar], completion: @escaping ([EKReminder]) -> Void) {
    let predicate = store.predicateForReminders(in: calendars)
    store.fetchReminders(matching: predicate) { reminders in
        completion(reminders ?? [])
    }
}

// MARK: - Commands

func listAllLists() {
    let calendars = store.calendars(for: .reminder)
    for calendar in calendars.sorted(by: { $0.title < $1.title }) {
        print(calendar.title)
    }
}

func listItems(listName: String, onlyIncomplete: Bool = false) {
    guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName }) else {
        fputs("List '\(listName)' not found.\n", stderr)
        exit(1)
    }
    let semaphore = DispatchSemaphore(value: 0)
    fetchAll(from: [calendar]) { reminders in
        let filtered = onlyIncomplete ? reminders.filter { !$0.isCompleted } : reminders
        let sorted = filtered.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        sorted.forEach { formatReminder($0) }
        semaphore.signal()
    }
    semaphore.wait()
}

func showToday() {
    let calendars = store.calendars(for: .reminder)
    let semaphore = DispatchSemaphore(value: 0)
    fetchAll(from: calendars) { reminders in
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let due = reminders.filter { reminder in
            guard !reminder.isCompleted,
                  let comps = reminder.dueDateComponents,
                  let date = Calendar.current.date(from: comps) else { return false }
            return date >= today && date < tomorrow
        }.sorted { ($0.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? .distantFuture)
                 < ($1.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? .distantFuture) }
        if due.isEmpty {
            print("No reminders due today.")
        } else {
            print("\(due.count) reminder(s) due today:")
            due.forEach { formatReminder($0) }
        }
        semaphore.signal()
    }
    semaphore.wait()
}

func showOverdue() {
    let calendars = store.calendars(for: .reminder)
    let semaphore = DispatchSemaphore(value: 0)
    fetchAll(from: calendars) { reminders in
        let now = Date()
        let overdue = reminders.filter { reminder in
            guard !reminder.isCompleted,
                  let comps = reminder.dueDateComponents,
                  let date = Calendar.current.date(from: comps) else { return false }
            return date < now
        }.sorted { ($0.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? .distantPast)
                 < ($1.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? .distantPast) }
        if overdue.isEmpty {
            print("No overdue reminders.")
        } else {
            print("\(overdue.count) overdue reminder(s):")
            overdue.forEach { formatReminder($0) }
        }
        semaphore.signal()
    }
    semaphore.wait()
}

func searchReminders(query: String) {
    let calendars = store.calendars(for: .reminder)
    let semaphore = DispatchSemaphore(value: 0)
    let lower = query.lowercased()
    fetchAll(from: calendars) { reminders in
        let matches = reminders.filter { reminder in
            (reminder.title?.lowercased().contains(lower) ?? false) ||
            (reminder.notes?.lowercased().contains(lower) ?? false)
        }.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        if matches.isEmpty {
            print("No reminders found for '\(query)'.")
        } else {
            print("\(matches.count) result(s) for '\(query)':")
            matches.forEach { formatReminder($0) }
        }
        semaphore.signal()
    }
    semaphore.wait()
}

func createList(listName: String) {
    let calendar = EKCalendar(for: .reminder, eventStore: store)
    calendar.title = listName
    calendar.source = store.defaultCalendarForNewReminders()?.source
    do {
        try store.saveCalendar(calendar, commit: true)
        print("Created list: \(listName)")
    } catch {
        fputs("Error creating list: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

func addReminder(listName: String, title: String, notes: String? = nil) {
    guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName }) else {
        fputs("List '\(listName)' not found.\n", stderr)
        exit(1)
    }
    let reminder = EKReminder(eventStore: store)
    reminder.title = title
    reminder.notes = notes
    reminder.calendar = calendar
    do {
        try store.save(reminder, commit: true)
        print("Added: \(title)")
    } catch {
        fputs("Error saving reminder: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

func setDueDate(listName: String, title: String, dateString: String) {
    guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName }) else {
        fputs("List '\(listName)' not found.\n", stderr)
        exit(1)
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    guard let date = formatter.date(from: dateString) else {
        fputs("Invalid date format. Use: YYYY-MM-DD HH:mm\n", stderr)
        exit(1)
    }
    let semaphore = DispatchSemaphore(value: 0)
    fetchAll(from: [calendar]) { reminders in
        guard let match = reminders.first(where: { $0.title == title && !$0.isCompleted }) else {
            fputs("Reminder '\(title)' not found or already completed.\n", stderr)
            semaphore.signal()
            return
        }
        match.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        do {
            try store.save(match, commit: true)
            print("Updated due date: \(title) → \(dateString)")
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
        }
        semaphore.signal()
    }
    semaphore.wait()
}

func setNotes(listName: String, title: String, notes: String) {
    guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName }) else {
        fputs("List '\(listName)' not found.\n", stderr)
        exit(1)
    }
    let semaphore = DispatchSemaphore(value: 0)
    fetchAll(from: [calendar]) { reminders in
        guard let match = reminders.first(where: { $0.title == title && !$0.isCompleted }) else {
            fputs("Reminder '\(title)' not found or already completed.\n", stderr)
            semaphore.signal()
            return
        }
        match.notes = notes
        do {
            try store.save(match, commit: true)
            print("Updated notes: \(title)")
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
        }
        semaphore.signal()
    }
    semaphore.wait()
}

func completeReminder(listName: String, title: String) {
    guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName }) else {
        fputs("List '\(listName)' not found.\n", stderr)
        exit(1)
    }
    let semaphore = DispatchSemaphore(value: 0)
    fetchAll(from: [calendar]) { reminders in
        guard let match = reminders.first(where: { $0.title == title && !$0.isCompleted }) else {
            fputs("Reminder '\(title)' not found or already completed.\n", stderr)
            semaphore.signal()
            return
        }
        match.isCompleted = true
        do {
            try store.save(match, commit: true)
            print("Completed: \(title)")
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
        }
        semaphore.signal()
    }
    semaphore.wait()
}

func deleteReminder(listName: String, title: String, force: Bool) {
    guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName }) else {
        fputs("List '\(listName)' not found.\n", stderr)
        exit(1)
    }
    let semaphore = DispatchSemaphore(value: 0)
    fetchAll(from: [calendar]) { reminders in
        guard let match = reminders.first(where: { $0.title == title }) else {
            fputs("Reminder '\(title)' not found.\n", stderr)
            semaphore.signal()
            return
        }
        guard force else {
            print("Would delete: \(title) (list: \(listName))")
            print("Re-run with --force to actually delete.")
            semaphore.signal()
            return
        }
        do {
            try store.remove(match, commit: true)
            print("Deleted: \(title)")
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
        }
        semaphore.signal()
    }
    semaphore.wait()
}

// MARK: - Main

let args = CommandLine.arguments

guard args.count >= 2 else {
    print("Usage:")
    print("  reminders-bridge lists")
    print("  reminders-bridge create-list <listName>")
    print("  reminders-bridge items <listName>")
    print("  reminders-bridge incomplete <listName>")
    print("  reminders-bridge today")
    print("  reminders-bridge overdue")
    print("  reminders-bridge search <query>")
    print("  reminders-bridge add <listName> <title> [notes]")
    print("  reminders-bridge set-due <listName> <title> <\"YYYY-MM-DD HH:mm\">")
    print("  reminders-bridge set-notes <listName> <title> <notes>")
    print("  reminders-bridge complete <listName> <title>")
    print("  reminders-bridge delete <listName> <title>")
    exit(0)
}

let accessSemaphore = DispatchSemaphore(value: 0)
var hasAccess = false

Task {
    hasAccess = await requestAccess()
    accessSemaphore.signal()
}
accessSemaphore.wait()

guard hasAccess else {
    fputs("No access to Reminders. Please grant permission in System Settings > Privacy & Security > Reminders.\n", stderr)
    exit(1)
}

let command = args[1]

switch command {
case "lists":
    listAllLists()

case "create-list":
    guard args.count >= 3 else { fputs("Usage: reminders-bridge create-list <listName>\n", stderr); exit(1) }
    createList(listName: args[2])

case "items":
    guard args.count >= 3 else { fputs("Usage: reminders-bridge items <listName>\n", stderr); exit(1) }
    listItems(listName: args[2])

case "incomplete":
    guard args.count >= 3 else { fputs("Usage: reminders-bridge incomplete <listName>\n", stderr); exit(1) }
    listItems(listName: args[2], onlyIncomplete: true)

case "today":
    showToday()

case "overdue":
    showOverdue()

case "search":
    guard args.count >= 3 else { fputs("Usage: reminders-bridge search <query>\n", stderr); exit(1) }
    searchReminders(query: args[2])

case "add":
    guard args.count >= 4 else { fputs("Usage: reminders-bridge add <listName> <title> [notes]\n", stderr); exit(1) }
    let notes = args.count >= 5 ? args[4] : nil
    addReminder(listName: args[2], title: args[3], notes: notes)

case "set-due":
    guard args.count >= 5 else { fputs("Usage: reminders-bridge set-due <listName> <title> <\"YYYY-MM-DD HH:mm\">\n", stderr); exit(1) }
    setDueDate(listName: args[2], title: args[3], dateString: args[4])

case "set-notes":
    guard args.count >= 5 else { fputs("Usage: reminders-bridge set-notes <listName> <title> <notes>\n", stderr); exit(1) }
    setNotes(listName: args[2], title: args[3], notes: args[4])

case "complete":
    guard args.count >= 4 else { fputs("Usage: reminders-bridge complete <listName> <title>\n", stderr); exit(1) }
    completeReminder(listName: args[2], title: args[3])

case "delete":
    guard args.count >= 4 else { fputs("Usage: reminders-bridge delete <listName> <title> [--force]\n", stderr); exit(1) }
    let force = args.contains("--force")
    deleteReminder(listName: args[2], title: args[3], force: force)

default:
    fputs("Unknown command: \(command)\n", stderr)
    exit(1)
}
