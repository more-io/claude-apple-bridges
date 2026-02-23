#!/usr/bin/env swift

// contacts-bridge.swift
// Copyright © 2026 Tobias Stöger (tstoegi). Licensed under the MIT License.
// A small CLI bridge for Claude Code to access Apple Contacts via Contacts framework.
// Usage:
//   contacts-bridge search <query>                                  - Search by name, email or phone
//   contacts-bridge show <name>                                     - Show full details for a contact
//   contacts-bridge add <firstName> <lastName> [phone] [email]      - Add a new contact
//   contacts-bridge update <name> phone <value>                     - Update phone number
//   contacts-bridge update <name> email <value>                     - Update email address
//   contacts-bridge delete <name> [--force]                         - Delete a contact
//   contacts-bridge birthdays-today                                 - Contacts with birthday today
//   contacts-bridge birthdays-upcoming <days>                       - Upcoming birthdays in N days

import Contacts
import Foundation

let store = CNContactStore()

func requestAccess() async -> Bool {
    do {
        return try await store.requestAccess(for: .contacts)
    } catch {
        fputs("Error requesting access: \(error.localizedDescription)\n", stderr)
        return false
    }
}

// MARK: - Helpers

let fetchKeys: [CNKeyDescriptor] = [
    CNContactGivenNameKey as CNKeyDescriptor,
    CNContactFamilyNameKey as CNKeyDescriptor,
    CNContactOrganizationNameKey as CNKeyDescriptor,
    CNContactPhoneNumbersKey as CNKeyDescriptor,
    CNContactEmailAddressesKey as CNKeyDescriptor,
    CNContactBirthdayKey as CNKeyDescriptor,
    CNContactPostalAddressesKey as CNKeyDescriptor,
]

func fullName(_ contact: CNContact) -> String {
    "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
}

func formatContact(_ contact: CNContact, detailed: Bool = false) {
    let org = contact.organizationName.isEmpty ? "" : " (\(contact.organizationName))"
    print("\(fullName(contact))\(org)")

    for phone in contact.phoneNumbers {
        let label = phone.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? ""
        print("  📞 \(phone.value.stringValue)\(label.isEmpty ? "" : "  [\(label)]")")
    }

    for email in contact.emailAddresses {
        let label = email.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? ""
        print("  ✉️  \(email.value)\(label.isEmpty ? "" : "  [\(label)]")")
    }

    if detailed {
        if contact.isKeyAvailable(CNContactNoteKey), !contact.note.isEmpty {
            print("  📝 \(contact.note)")
        }
        if let bday = contact.birthday, let day = bday.day, let month = bday.month {
            let year = bday.year.map { " \($0)" } ?? ""
            print("  🎂 \(day).\(month).\(year)")
        }
        for address in contact.postalAddresses {
            let a = address.value
            let line = [a.street, a.postalCode, a.city, a.country]
                .filter { !$0.isEmpty }.joined(separator: ", ")
            print("  🏠 \(line)")
        }
    }
}

func findContacts(matching name: String) throws -> [CNContact] {
    let predicate = CNContact.predicateForContacts(matchingName: name)
    return try store.unifiedContacts(matching: predicate, keysToFetch: fetchKeys)
}

// MARK: - Commands

func searchContacts(query: String) {
    do {
        let contacts = try findContacts(matching: query)
        if contacts.isEmpty { print("No contacts found for '\(query)'"); return }
        print("\(contacts.count) result(s) for '\(query)':")
        print(String(repeating: "-", count: 40))
        contacts.forEach { formatContact($0); print() }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
    }
}

func showContact(name: String) {
    do {
        let contacts = try findContacts(matching: name)
        if contacts.isEmpty { print("No contact found for '\(name)'"); return }
        contacts.forEach { formatContact($0, detailed: true); print() }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
    }
}

func addContact(firstName: String, lastName: String, phone: String?, email: String?) {
    let contact = CNMutableContact()
    contact.givenName = firstName
    contact.familyName = lastName
    if let phone {
        contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))]
    }
    if let email {
        contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
    }
    let saveRequest = CNSaveRequest()
    saveRequest.add(contact, toContainerWithIdentifier: nil)
    do {
        try store.execute(saveRequest)
        print("Added contact: \(firstName) \(lastName)".trimmingCharacters(in: .whitespaces))
    } catch {
        fputs("Error saving contact: \(error.localizedDescription)\n", stderr); exit(1)
    }
}

func updateContact(name: String, field: String, value: String) {
    do {
        let contacts = try findContacts(matching: name)
        guard let contact = contacts.first else {
            fputs("Contact '\(name)' not found.\n", stderr); exit(1)
        }
        guard let mutable = contact.mutableCopy() as? CNMutableContact else { exit(1) }

        switch field.lowercased() {
        case "phone":
            mutable.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: value))]
        case "email":
            mutable.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: value as NSString)]
        default:
            fputs("Unknown field '\(field)'. Use 'phone' or 'email'.\n", stderr); exit(1)
        }

        let saveRequest = CNSaveRequest()
        saveRequest.update(mutable)
        try store.execute(saveRequest)
        print("Updated \(field) for \(fullName(contact)): \(value)")
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
    }
}

func deleteContact(name: String, force: Bool) {
    do {
        let contacts = try findContacts(matching: name)
        guard let contact = contacts.first else {
            fputs("Contact '\(name)' not found.\n", stderr); exit(1)
        }
        guard force else {
            print("Would delete contact: \(fullName(contact))")
            if !contact.phoneNumbers.isEmpty {
                print("  📞 \(contact.phoneNumbers.map { $0.value.stringValue }.joined(separator: ", "))")
            }
            if !contact.emailAddresses.isEmpty {
                print("  ✉️  \(contact.emailAddresses.map { $0.value as String }.joined(separator: ", "))")
            }
            print("Re-run with --force to actually delete.")
            return
        }
        guard let mutable = contact.mutableCopy() as? CNMutableContact else { exit(1) }
        let saveRequest = CNSaveRequest()
        saveRequest.delete(mutable)
        try store.execute(saveRequest)
        print("Deleted contact: \(fullName(contact))")
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
    }
}

func birthdaysToday() {
    let cal = Calendar.current
    let today = cal.dateComponents([.month, .day], from: Date())

    do {
        let allContacts = try store.unifiedContacts(
            matching: CNContact.predicateForContactsInContainer(withIdentifier: store.defaultContainerIdentifier()),
            keysToFetch: fetchKeys
        )
        let matches = allContacts.filter { contact in
            guard let bday = contact.birthday,
                  let month = bday.month, let day = bday.day else { return false }
            return month == today.month && day == today.day
        }
        if matches.isEmpty {
            print("No birthdays today.")
        } else {
            print("\(matches.count) birthday(s) today:")
            matches.forEach { formatContact($0); print() }
        }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
    }
}

func birthdaysUpcoming(days: Int) {
    let cal = Calendar.current
    let today = Date()

    do {
        let allContacts = try store.unifiedContacts(
            matching: CNContact.predicateForContactsInContainer(withIdentifier: store.defaultContainerIdentifier()),
            keysToFetch: fetchKeys
        )

        var upcoming: [(contact: CNContact, daysUntil: Int, date: DateComponents)] = []

        for contact in allContacts {
            guard let bday = contact.birthday,
                  let month = bday.month, let day = bday.day else { continue }

            let currentYear = cal.component(.year, from: today)
            for yearOffset in 0...1 {
                var nextBday = DateComponents()
                nextBday.year = currentYear + yearOffset
                nextBday.month = month
                nextBday.day = day
                if let bdayDate = cal.date(from: nextBday) {
                    let diff = cal.dateComponents([.day], from: cal.startOfDay(for: today), to: cal.startOfDay(for: bdayDate)).day ?? 0
                    if diff >= 0 && diff <= days {
                        upcoming.append((contact, diff, bday))
                        break
                    }
                }
            }
        }

        upcoming.sort { $0.daysUntil < $1.daysUntil }

        if upcoming.isEmpty {
            print("No birthdays in the next \(days) days.")
        } else {
            print("\(upcoming.count) birthday(s) in the next \(days) days:")
            for entry in upcoming {
                let when = entry.daysUntil == 0 ? "Today" : entry.daysUntil == 1 ? "Tomorrow" : "In \(entry.daysUntil) days"
                let year = entry.date.year.map { " \($0)" } ?? ""
                print("  \(when) (\(entry.date.day!).\(entry.date.month!)\(year)): \(fullName(entry.contact))")
            }
        }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr); exit(1)
    }
}

// MARK: - Main

let args = CommandLine.arguments

guard args.count >= 2 else {
    print("Usage:")
    print("  contacts-bridge search <query>")
    print("  contacts-bridge show <name>")
    print("  contacts-bridge add <firstName> <lastName> [phone] [email]")
    print("  contacts-bridge update <name> phone <value>")
    print("  contacts-bridge update <name> email <value>")
    print("  contacts-bridge delete <name> [--force]")
    print("  contacts-bridge birthdays-today")
    print("  contacts-bridge birthdays-upcoming <days>")
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
    fputs("No access to Contacts. Please grant permission in System Settings > Privacy & Security > Contacts.\n", stderr)
    exit(1)
}

let command = args[1]

switch command {
case "search":
    guard args.count >= 3 else { fputs("Usage: contacts-bridge search <query>\n", stderr); exit(1) }
    searchContacts(query: args[2])

case "show":
    guard args.count >= 3 else { fputs("Usage: contacts-bridge show <name>\n", stderr); exit(1) }
    showContact(name: args[2])

case "add":
    guard args.count >= 4 else { fputs("Usage: contacts-bridge add <firstName> <lastName> [phone] [email]\n", stderr); exit(1) }
    let phone = args.count >= 5 ? args[4] : nil
    let email = args.count >= 6 ? args[5] : nil
    addContact(firstName: args[2], lastName: args[3], phone: phone, email: email)

case "update":
    guard args.count >= 5 else { fputs("Usage: contacts-bridge update <name> phone|email <value>\n", stderr); exit(1) }
    updateContact(name: args[2], field: args[3], value: args[4])

case "delete":
    guard args.count >= 3 else { fputs("Usage: contacts-bridge delete <name> [--force]\n", stderr); exit(1) }
    let force = args.contains("--force")
    deleteContact(name: args[2], force: force)

case "birthdays-today":
    birthdaysToday()

case "birthdays-upcoming":
    guard args.count >= 3, let days = Int(args[2]) else {
        fputs("Usage: contacts-bridge birthdays-upcoming <days>\n", stderr); exit(1)
    }
    birthdaysUpcoming(days: days)

default:
    fputs("Unknown command: \(command)\n", stderr)
    exit(1)
}
