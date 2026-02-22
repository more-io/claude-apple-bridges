#!/usr/bin/env swift

// calendar-bridge.swift
// Copyright © 2026 Tobias Stöger (tstoegi). Licensed under the MIT License.
// A small CLI bridge for Claude Code to access Apple Calendar via EventKit.
// Usage:
//   calendar-bridge calendars                                      - List all calendars
//   calendar-bridge today                                          - Show today's events
//   calendar-bridge tomorrow                                       - Show tomorrow's events
//   calendar-bridge week                                           - Show this week's events
//   calendar-bridge events <YYYY-MM-DD>                            - Show events for a date
//   calendar-bridge free-slots <YYYY-MM-DD>                        - Show free time slots for a date
//   calendar-bridge search <query>                                 - Search events by title (next 365 days)
//   calendar-bridge add <cal> <title> <start> <end>                - Add event (YYYY-MM-DD HH:mm)
//   calendar-bridge add-all-day <cal> <title> <YYYY-MM-DD>         - Add all-day event
//   calendar-bridge delete <cal> <title> <YYYY-MM-DD> [--force]    - Delete an event

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

func formatTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

func formatDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE dd.MM. HH:mm"
    formatter.locale = Locale.current
    return formatter.string(from: date)
}

func formatDayHeader(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, dd. MMMM yyyy"
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
    print("Events for \(formatDayHeader(date)):")
    if events.isEmpty {
        print("  (no events)")
        return
    }
    for event in events {
        let timeStr = event.isAllDay ? "All day" : "\(formatTime(event.startDate)) – \(formatTime(event.endDate))"
        let loc = event.location.map { " @ \($0)" } ?? ""
        print("  [\(timeStr)] \(event.title ?? "(no title)")\(loc)  (\(event.calendar.title))")
    }
}

func showWeek() {
    let cal = Calendar.current
    let today = Date()
    // Start from Monday of current week
    var components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
    components.weekday = 2 // Monday
    let monday = cal.date(from: components) ?? today

    for offset in 0..<7 {
        let day = cal.date(byAdding: .day, value: offset, to: monday)!
        showEvents(for: day)
        print()
    }
}

func showFreeSlots(for date: Date) {
    let predicate = store.predicateForEvents(withStart: startOfDay(date), end: endOfDay(date), calendars: nil)
    let events = store.events(matching: predicate)
        .filter { !$0.isAllDay }
        .sorted { $0.startDate < $1.startDate }

    print("Free slots on \(formatDayHeader(date)):")

    // Working hours 08:00–20:00, minimum slot 30 min
    let workStart = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: date)!
    let workEnd   = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: date)!
    let minSlot: TimeInterval = 30 * 60

    var cursor = workStart
    var hasSlots = false

    for event in events {
        let eventStart = max(event.startDate, workStart)
        let eventEnd   = min(event.endDate, workEnd)
        if eventStart > cursor && eventStart.timeIntervalSince(cursor) >= minSlot {
            print("  \(formatTime(cursor)) – \(formatTime(eventStart))  (\(Int(eventStart.timeIntervalSince(cursor) / 60)) min)")
            hasSlots = true
        }
        if eventEnd > cursor { cursor = eventEnd }
    }

    if workEnd > cursor && workEnd.timeIntervalSince(cursor) >= minSlot {
        print("  \(formatTime(cursor)) – \(formatTime(workEnd))  (\(Int(workEnd.timeIntervalSince(cursor) / 60)) min)")
        hasSlots = true
    }

    if !hasSlots {
        print("  (no free slots in working hours 08:00–20:00)")
    }
}

func searchEvents(query: String) {
    let lower = query.lowercased()
    let start = Date()
    let end = Calendar.current.date(byAdding: .day, value: 365, to: start)!
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    let matches = store.events(matching: predicate)
        .filter { ($0.title ?? "").lowercased().contains(lower) }
        .sorted { $0.startDate < $1.startDate }

    if matches.isEmpty {
        print("No events found for '\(query)' in the next 365 days.")
        return
    }
    print("\(matches.count) event(s) matching '\(query)':")
    for event in matches {
        let timeStr = event.isAllDay ? "All day" : "\(formatDateTime(event.startDate)) – \(formatTime(event.endDate))"
        print("  [\(timeStr)] \(event.title ?? "(no title)")  (\(event.calendar.title))")
    }
}

func addEvent(calendarName: String, title: String, start: Date, end: Date) {
    guard let calendar = store.calendars(for: .event).first(where: { $0.title == calendarName }) else {
        fputs("Calendar '\(calendarName)' not found.\n", stderr); exit(1)
    }
    guard !calendar.isImmutable else {
        fputs("Calendar '\(calendarName)' is read-only.\n", stderr); exit(1)
    }
    let event = EKEvent(eventStore: store)
    event.title = title
    event.startDate = start
    event.endDate = end
    event.calendar = calendar
    do {
        try store.save(event, span: .thisEvent)
        print("Added: \(title) (\(formatDateTime(start)) – \(formatTime(end)))")
    } catch {
        fputs("Error saving event: \(error.localizedDescription)\n", stderr); exit(1)
    }
}

func addAllDayEvent(calendarName: String, title: String, date: Date) {
    guard let calendar = store.calendars(for: .event).first(where: { $0.title == calendarName }) else {
        fputs("Calendar '\(calendarName)' not found.\n", stderr); exit(1)
    }
    guard !calendar.isImmutable else {
        fputs("Calendar '\(calendarName)' is read-only.\n", stderr); exit(1)
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
        fputs("Error saving event: \(error.localizedDescription)\n", stderr); exit(1)
    }
}

func deleteEvent(calendarName: String, title: String, date: Date, force: Bool) {
    guard let calendar = store.calendars(for: .event).first(where: { $0.title == calendarName }) else {
        fputs("Calendar '\(calendarName)' not found.\n", stderr); exit(1)
    }
    let predicate = store.predicateForEvents(withStart: startOfDay(date), end: endOfDay(date), calendars: [calendar])
    let matches = store.events(matching: predicate).filter { ($0.title ?? "") == title }

    guard let event = matches.first else {
        fputs("Event '\(title)' not found on \(formatDayHeader(date)).\n", stderr); exit(1)
    }
    guard force else {
        print("Would delete: \(title) on \(formatDayHeader(date)) (\(formatTime(event.startDate)) – \(formatTime(event.endDate)))")
        print("Re-run with --force to actually delete.")
        return
    }
    do {
        try store.remove(event, span: .thisEvent)
        print("Deleted: \(title) on \(formatDayHeader(date))")
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
    }
}

// MARK: - Main

let args = CommandLine.arguments

guard args.count >= 2 else {
    print("Usage:")
    print("  calendar-bridge calendars")
    print("  calendar-bridge today")
    print("  calendar-bridge tomorrow")
    print("  calendar-bridge week")
    print("  calendar-bridge events <YYYY-MM-DD>")
    print("  calendar-bridge free-slots <YYYY-MM-DD>")
    print("  calendar-bridge search <query>")
    print("  calendar-bridge add <calendar> <title> <\"YYYY-MM-DD HH:mm\"> <\"YYYY-MM-DD HH:mm\">")
    print("  calendar-bridge add-all-day <calendar> <title> <YYYY-MM-DD>")
    print("  calendar-bridge delete <calendar> <title> <YYYY-MM-DD> [--force]")
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

case "week":
    showWeek()

case "events":
    guard args.count >= 3, let date = parseDate(args[2]) else {
        fputs("Usage: calendar-bridge events <YYYY-MM-DD>\n", stderr); exit(1)
    }
    showEvents(for: date)

case "free-slots":
    guard args.count >= 3, let date = parseDate(args[2]) else {
        fputs("Usage: calendar-bridge free-slots <YYYY-MM-DD>\n", stderr); exit(1)
    }
    showFreeSlots(for: date)

case "search":
    guard args.count >= 3 else {
        fputs("Usage: calendar-bridge search <query>\n", stderr); exit(1)
    }
    searchEvents(query: args[2])

case "add":
    guard args.count >= 6,
          let start = parseDateTime(args[4]),
          let end = parseDateTime(args[5]) else {
        fputs("Usage: calendar-bridge add <calendar> <title> <\"YYYY-MM-DD HH:mm\"> <\"YYYY-MM-DD HH:mm\">\n", stderr); exit(1)
    }
    addEvent(calendarName: args[2], title: args[3], start: start, end: end)

case "add-all-day":
    guard args.count >= 5, let date = parseDate(args[4]) else {
        fputs("Usage: calendar-bridge add-all-day <calendar> <title> <YYYY-MM-DD>\n", stderr); exit(1)
    }
    addAllDayEvent(calendarName: args[2], title: args[3], date: date)

case "delete":
    guard args.count >= 5, let date = parseDate(args[4]) else {
        fputs("Usage: calendar-bridge delete <calendar> <title> <YYYY-MM-DD> [--force]\n", stderr); exit(1)
    }
    let force = args.contains("--force")
    deleteEvent(calendarName: args[2], title: args[3], date: date, force: force)

default:
    fputs("Unknown command: \(command)\n", stderr)
    exit(1)
}
