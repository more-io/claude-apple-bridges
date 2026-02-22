#!/usr/bin/env swift

// calendar-bridge.swift
// Copyright © 2026 Tobias Stöger (tstoegi). Licensed under the MIT License.
// A small CLI bridge for Claude Code to access Apple Calendar via EventKit.
// Usage:
//   calendar-bridge calendars                                    - List all calendars
//   calendar-bridge today                                        - Show today's events
//   calendar-bridge tomorrow                                     - Show tomorrow's events
//   calendar-bridge events <date>                                - Show events for date (YYYY-MM-DD)
//   calendar-bridge add <calendar> <title> <start> <end>        - Add event (start/end: YYYY-MM-DD HH:mm)
//   calendar-bridge add-all-day <calendar> <title> <date>       - Add all-day event (YYYY-MM-DD)

import EventKit
import Foundation

let store = EKEventStore()

func requestAccess() async -> Bool {
    do {
        return try await store.requestFullAccessToEvents()
    } catch {
        fputs("Error requesting access: \(error.localizedDescription)\n", stderr)
        return false
    }
}

// MARK: - Date Helpers

func parseDateTime(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.date(from: string)
}

func parseDate(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.date(from: string)
}

func formatDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE dd.MM. HH:mm"
    formatter.locale = Locale.current
    return formatter.string(from: date)
}

func startOfDay(_ date: Date) -> Date {
    Calendar.current.startOfDay(for: date)
}

func endOfDay(_ date: Date) -> Date {
    var components = DateComponents()
    components.day = 1
    components.second = -1
    return Calendar.current.date(byAdding: components, to: startOfDay(date))!
}

// MARK: - Commands

func listCalendars() {
    let calendars = store.calendars(for: .event)
    for cal in calendars.sorted(by: { $0.title < $1.title }) {
        let type = cal.isImmutable ? " (read-only)" : ""
        print("\(cal.title)\(type)")
    }
}

func showEvents(for date: Date) {
    let predicate = store.predicateForEvents(withStart: startOfDay(date), end: endOfDay(date), calendars: nil)
    let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

    let dayFormatter = DateFormatter()
    dayFormatter.dateFormat = "EEEE, dd. MMMM yyyy"
    dayFormatter.locale = Locale(identifier: "de_DE")
    print("Events for \(dayFormatter.string(from: date)):")

    if events.isEmpty {
        print("  (no events)")
        return
    }

    for event in events {
        let timeStr: String
        if event.isAllDay {
            timeStr = "All day"
        } else {
            let start = DateFormatter()
            start.dateFormat = "HH:mm"
            let end = DateFormatter()
            end.dateFormat = "HH:mm"
            timeStr = "\(start.string(from: event.startDate)) – \(end.string(from: event.endDate))"
        }
        let cal = event.calendar.title
        let loc = event.location.map { " @ \($0)" } ?? ""
        print("  [\(timeStr)] \(event.title ?? "(no title)")\(loc)  (\(cal))")
    }
}

func addEvent(calendarName: String, title: String, start: Date, end: Date) {
    guard let calendar = store.calendars(for: .event).first(where: { $0.title == calendarName }) else {
        fputs("Calendar '\(calendarName)' not found.\n", stderr)
        exit(1)
    }

    guard !calendar.isImmutable else {
        fputs("Calendar '\(calendarName)' is read-only.\n", stderr)
        exit(1)
    }

    let event = EKEvent(eventStore: store)
    event.title = title
    event.startDate = start
    event.endDate = end
    event.calendar = calendar

    do {
        try store.save(event, span: .thisEvent)
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        print("Added: \(title) (\(formatDateTime(start)) – \(fmt.string(from: end)))")
    } catch {
        fputs("Error saving event: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

func addAllDayEvent(calendarName: String, title: String, date: Date) {
    guard let calendar = store.calendars(for: .event).first(where: { $0.title == calendarName }) else {
        fputs("Calendar '\(calendarName)' not found.\n", stderr)
        exit(1)
    }

    guard !calendar.isImmutable else {
        fputs("Calendar '\(calendarName)' is read-only.\n", stderr)
        exit(1)
    }

    let event = EKEvent(eventStore: store)
    event.title = title
    event.isAllDay = true
    event.startDate = startOfDay(date)
    event.endDate = startOfDay(date)
    event.calendar = calendar

    do {
        try store.save(event, span: .thisEvent)
        let fmt = DateFormatter()
        fmt.dateFormat = "dd.MM.yyyy"
        print("Added all-day: \(title) (\(fmt.string(from: date)))")
    } catch {
        fputs("Error saving event: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

// MARK: - Main

let args = CommandLine.arguments

guard args.count >= 2 else {
    print("Usage:")
    print("  calendar-bridge calendars")
    print("  calendar-bridge today")
    print("  calendar-bridge tomorrow")
    print("  calendar-bridge events <YYYY-MM-DD>")
    print("  calendar-bridge add <calendar> <title> <\"YYYY-MM-DD HH:mm\"> <\"YYYY-MM-DD HH:mm\">")
    print("  calendar-bridge add-all-day <calendar> <title> <YYYY-MM-DD>")
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
    fputs("No access to Calendar. Please grant permission in System Settings > Privacy & Security > Calendars.\n", stderr)
    exit(1)
}

let command = args[1]

switch command {
case "calendars":
    listCalendars()

case "today":
    showEvents(for: Date())

case "tomorrow":
    showEvents(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)

case "events":
    guard args.count >= 3, let date = parseDate(args[2]) else {
        fputs("Usage: calendar-bridge events <YYYY-MM-DD>\n", stderr)
        exit(1)
    }
    showEvents(for: date)

case "add":
    guard args.count >= 6,
          let start = parseDateTime(args[4]),
          let end = parseDateTime(args[5]) else {
        fputs("Usage: calendar-bridge add <calendar> <title> <\"YYYY-MM-DD HH:mm\"> <\"YYYY-MM-DD HH:mm\">\n", stderr)
        exit(1)
    }
    addEvent(calendarName: args[2], title: args[3], start: start, end: end)

case "add-all-day":
    guard args.count >= 5, let date = parseDate(args[4]) else {
        fputs("Usage: calendar-bridge add-all-day <calendar> <title> <YYYY-MM-DD>\n", stderr)
        exit(1)
    }
    addAllDayEvent(calendarName: args[2], title: args[3], date: date)

default:
    fputs("Unknown command: \(command)\n", stderr)
    exit(1)
}
