#!/usr/bin/env swift

// contacts-bridge.swift
// Copyright © 2026 Tobias Stöger (tstoegi). Licensed under the MIT License.
// A small CLI bridge for Claude Code to access Apple Contacts via Contacts framework.
// Usage:
//   contacts-bridge search <query>           - Search contacts by name, email or phone
//   contacts-bridge show <name>              - Show full details for a contact
//   contacts-bridge add <firstName> <lastName> [phone] [email]  - Add a new contact

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
    CNContactNoteKey as CNKeyDescriptor,
    CNContactBirthdayKey as CNKeyDescriptor,
    CNContactPostalAddressesKey as CNKeyDescriptor,
]

func formatContact(_ contact: CNContact, detailed: Bool = false) {
    let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
    let org = contact.organizationName.isEmpty ? "" : " (\(contact.organizationName))"
    print("\(name)\(org)")

    for phone in contact.phoneNumbers {
        let label = phone.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? ""
        print("  📞 \(phone.value.stringValue)\(label.isEmpty ? "" : "  [\(label)]")")
    }

    for email in contact.emailAddresses {
        let label = email.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? ""
        print("  ✉️  \(email.value)\(label.isEmpty ? "" : "  [\(label)]")")
    }

    if detailed {
        if !contact.note.isEmpty {
            print("  📝 \(contact.note)")
        }
        if let bday = contact.birthday,
           let day = bday.day, let month = bday.month {
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

// MARK: - Commands

func searchContacts(query: String) {
    let predicate = CNContact.predicateForContacts(matchingName: query)
    do {
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: fetchKeys)
        if contacts.isEmpty {
            print("No contacts found for '\(query)'")
            return
        }
        print("\(contacts.count) result(s) for '\(query)':")
        print(String(repeating: "-", count: 40))
        contacts.forEach { contact in
            formatContact(contact)
            print()
        }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

func showContact(name: String) {
    let predicate = CNContact.predicateForContacts(matchingName: name)
    do {
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: fetchKeys)
        if contacts.isEmpty {
            print("No contact found for '\(name)'")
            return
        }
        contacts.forEach { contact in
            formatContact(contact, detailed: true)
            print()
        }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

func addContact(firstName: String, lastName: String, phone: String?, email: String?) {
    let contact = CNMutableContact()
    contact.givenName = firstName
    contact.familyName = lastName

    if let phone {
        contact.phoneNumbers = [CNLabeledValue(
            label: CNLabelPhoneNumberMobile,
            value: CNPhoneNumber(stringValue: phone)
        )]
    }

    if let email {
        contact.emailAddresses = [CNLabeledValue(
            label: CNLabelWork,
            value: email as NSString
        )]
    }

    let saveRequest = CNSaveRequest()
    saveRequest.add(contact, toContainerWithIdentifier: nil)

    do {
        try store.execute(saveRequest)
        let name = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        print("Added contact: \(name)")
    } catch {
        fputs("Error saving contact: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

// MARK: - Main

let args = CommandLine.arguments

guard args.count >= 2 else {
    print("Usage:")
    print("  contacts-bridge search <query>")
    print("  contacts-bridge show <name>")
    print("  contacts-bridge add <firstName> <lastName> [phone] [email]")
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
    guard args.count >= 3 else {
        fputs("Usage: contacts-bridge search <query>\n", stderr)
        exit(1)
    }
    searchContacts(query: args[2])

case "show":
    guard args.count >= 3 else {
        fputs("Usage: contacts-bridge show <name>\n", stderr)
        exit(1)
    }
    showContact(name: args[2])

case "add":
    guard args.count >= 4 else {
        fputs("Usage: contacts-bridge add <firstName> <lastName> [phone] [email]\n", stderr)
        exit(1)
    }
    let phone = args.count >= 5 ? args[4] : nil
    let email = args.count >= 6 ? args[5] : nil
    addContact(firstName: args[2], lastName: args[3], phone: phone, email: email)

default:
    fputs("Unknown command: \(command)\n", stderr)
    exit(1)
}
