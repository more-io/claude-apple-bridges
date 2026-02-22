#!/usr/bin/env swift

// reminders-bridge.swift
// A small CLI bridge for Claude Code to access Apple Reminders via EventKit.
// Usage:
//   reminders-bridge lists                          - List all reminder lists
//   reminders-bridge items <listName>               - List reminders in a list
//   reminders-bridge add <listName> <title>         - Add a reminder
//   reminders-bridge complete <listName> <title>    - Mark a reminder as complete
//   reminders-bridge incomplete <listName>          - Show incomplete reminders in a list

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

    let predicate = store.predicateForReminders(in: [calendar])
    let semaphore = DispatchSemaphore(value: 0)

    store.fetchReminders(matching: predicate) { reminders in
        guard let reminders else {
            fputs("Failed to fetch reminders.\n", stderr)
            semaphore.signal()
            return
        }

        let filtered = onlyIncomplete ? reminders.filter { !$0.isCompleted } : reminders
        let sorted = filtered.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

        for reminder in sorted {
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
            case 5: priority = " !"
            case 6...9: priority = ""
            default: priority = ""
            }
            let recurrenceStr: String
            if let rules = reminder.recurrenceRules, let rule = rules.first {
                let freq: String
                switch rule.frequency {
                case .daily: freq = "daily"
                case .weekly: freq = "weekly"
                case .monthly: freq = "monthly"
                case .yearly: freq = "yearly"
                @unknown default: freq = "unknown"
                }
                let interval = rule.interval > 1 ? " (every \(rule.interval))" : ""
                let endStr: String
                if let end = rule.recurrenceEnd {
                    if let endDate = end.endDate {
                        let fmt = DateFormatter()
                        fmt.dateStyle = .short
                        endStr = ", until \(fmt.string(from: endDate))"
                    } else {
                        endStr = ", \(end.occurrenceCount)x"
                    }
                } else {
                    endStr = ""
                }
                recurrenceStr = " [repeats: \(freq)\(interval)\(endStr)]"
            } else {
                recurrenceStr = ""
            }
            let notesStr = (reminder.notes != nil && !reminder.notes!.isEmpty) ? "\n     Notes: \(reminder.notes!)" : ""
            print("\(status) \(reminder.title ?? "(no title)")\(priority)\(dueStr)\(recurrenceStr)\(notesStr)")
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

    let predicate = store.predicateForReminders(in: [calendar])
    let semaphore = DispatchSemaphore(value: 0)

    store.fetchReminders(matching: predicate) { reminders in
        guard let reminders else {
            fputs("Failed to fetch reminders.\n", stderr)
            semaphore.signal()
            return
        }

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

func completeReminder(listName: String, title: String) {
    guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName }) else {
        fputs("List '\(listName)' not found.\n", stderr)
        exit(1)
    }

    let predicate = store.predicateForReminders(in: [calendar])
    let semaphore = DispatchSemaphore(value: 0)

    store.fetchReminders(matching: predicate) { reminders in
        guard let reminders else {
            fputs("Failed to fetch reminders.\n", stderr)
            semaphore.signal()
            return
        }

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

// MARK: - Main

let args = CommandLine.arguments

guard args.count >= 2 else {
    print("Usage:")
    print("  reminders-bridge lists")
    print("  reminders-bridge create-list <listName>")
    print("  reminders-bridge items <listName>")
    print("  reminders-bridge incomplete <listName>")
    print("  reminders-bridge add <listName> <title> [notes]")
    print("  reminders-bridge complete <listName> <title>")
    exit(0)
}

// Request access synchronously via semaphore (since this is a CLI)
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
    guard args.count >= 3 else {
        fputs("Usage: reminders-bridge create-list <listName>\n", stderr)
        exit(1)
    }
    createList(listName: args[2])

case "items":
    guard args.count >= 3 else {
        fputs("Usage: reminders-bridge items <listName>\n", stderr)
        exit(1)
    }
    listItems(listName: args[2])

case "incomplete":
    guard args.count >= 3 else {
        fputs("Usage: reminders-bridge incomplete <listName>\n", stderr)
        exit(1)
    }
    listItems(listName: args[2], onlyIncomplete: true)

case "add":
    guard args.count >= 4 else {
        fputs("Usage: reminders-bridge add <listName> <title> [notes]\n", stderr)
        exit(1)
    }
    let notes = args.count >= 5 ? args[4] : nil
    addReminder(listName: args[2], title: args[3], notes: notes)

case "set-due":
    guard args.count >= 5 else {
        fputs("Usage: reminders-bridge set-due <listName> <title> <\"YYYY-MM-DD HH:mm\">\n", stderr)
        exit(1)
    }
    setDueDate(listName: args[2], title: args[3], dateString: args[4])

case "complete":
    guard args.count >= 4 else {
        fputs("Usage: reminders-bridge complete <listName> <title>\n", stderr)
        exit(1)
    }
    completeReminder(listName: args[2], title: args[3])

default:
    fputs("Unknown command: \(command)\n", stderr)
    exit(1)
}
