# Claude Apple Bridges

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![Platform: macOS 13+](https://img.shields.io/badge/Platform-macOS%2013%2B-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)

Swift CLI tools that give [Claude Code](https://claude.ai/claude-code) native access to Apple apps — Reminders, Calendar, Contacts, and Notes. Designed to be used as allowed tools in Claude Code's `settings.local.json`.

## Usage Examples with Claude Code

Once set up, you can ask Claude naturally in any Claude Code session. Here are real-world examples:

---

### Task & Project Management

> *"What's on my todo list for today?"*

Claude checks your Reminders and summarizes open items with due dates and priorities.

> *"I just finished the login bug fix — mark the GitHub issue and the reminder as done."*

Claude closes the GitHub issue and calls `reminders-bridge complete` in one step.

> *"Add a reminder to my 'Work' list to review the PR tomorrow morning."*

Claude creates the reminder with a due date set to tomorrow at 9:00.

---

### Calendar-Aware Scheduling

> *"I want to work on the Android release tomorrow — find a free slot and set a reminder."*

Claude checks `calendar-bridge tomorrow`, finds a free window, and sets the reminder due date accordingly — no double-booking.

> *"What do I have going on this week? Block some time for code review."*

Claude reads your calendar for each day, spots gaps, and adds events or reminders where they fit.

> *"Schedule our next planning session for next Monday at 10am in my Work calendar."*

Claude calls `calendar-bridge add` directly without you having to open Calendar.

---

### Contacts Lookup

> *"What's Rob's phone number?"*

Claude searches your Contacts and returns the number directly — no need to open the Contacts app.

> *"Add Alex to my contacts: +49 123 456789, alex@example.com"*

Claude calls `contacts-bridge add` and confirms once saved.

> *"Show me all details for my contact Thomas."*

Claude returns name, phone, email, address and birthday in one view.

---

### Development Workflow Integration

> *"Start working on issue #42 — create a reminder to track it and add the 'in progress' label."*

Claude adds a GitHub label, creates a Reminders entry with the issue number in the notes, and sets a due date.

> *"We finished the feature — close the issue, complete the reminder, and write the release note."*

Claude handles all three in one go.

> *"What are my open todos related to this project?"*

Claude reads your Reminders list and cross-references with open GitHub issues for a full picture.

---

### End-of-Day / Planning

> *"Summarize what we did today and create reminders for anything we didn't finish."*

Claude reviews the session, identifies incomplete work, and adds follow-up reminders with appropriate due dates.

> *"Set reminders for all open todos so they show up in my Calendar tomorrow after my meetings."*

Claude reads tomorrow's calendar first to avoid conflicts, then sets due times in the free slots.

---

## Bridges

### reminders-bridge
Access and manage Apple Reminders from Claude Code.

```
reminders-bridge lists                                   List all reminder lists
reminders-bridge create-list <name>                      Create a new list
reminders-bridge items <list>                            Show all reminders in a list
reminders-bridge incomplete <list>                       Show only incomplete reminders
reminders-bridge today                                   Show reminders due today (all lists)
reminders-bridge overdue                                 Show all overdue reminders (all lists)
reminders-bridge search <query>                          Search by title/notes across all lists
reminders-bridge add <list> <title> [notes]              Add a new reminder
reminders-bridge set-due <list> <title> <datetime>       Set due date (YYYY-MM-DD HH:mm)
reminders-bridge set-notes <list> <title> <notes>        Set or update notes
reminders-bridge complete <list> <title>                 Mark a reminder as complete
reminders-bridge delete <list> <title> [--force]         Delete a reminder (dry-run without --force)
```

### calendar-bridge
Read and write Apple Calendar events from Claude Code.

```
calendar-bridge calendars                                     List all calendars
calendar-bridge today                                         Show today's events
calendar-bridge tomorrow                                      Show tomorrow's events
calendar-bridge week                                          Show this week's events
calendar-bridge events <YYYY-MM-DD>                           Show events for a date
calendar-bridge free-slots <YYYY-MM-DD>                       Show free time slots (08:00–20:00)
calendar-bridge search <query>                                Search events by title (next 365 days)
calendar-bridge add <cal> <title> <start> <end>               Add event (YYYY-MM-DD HH:mm)
calendar-bridge add-all-day <cal> <title> <YYYY-MM-DD>        Add all-day event
calendar-bridge delete <cal> <title> <YYYY-MM-DD> [--force]   Delete event (dry-run without --force)
```

### contacts-bridge
Search and manage Apple Contacts from Claude Code.

```
contacts-bridge search <query>                                Search by name, email or phone
contacts-bridge show <name>                                   Show full details for a contact
contacts-bridge add <firstName> <lastName> [phone] [email]    Add a new contact
contacts-bridge update <name> phone <value>                   Update phone number
contacts-bridge update <name> email <value>                   Update email address
contacts-bridge delete <name> [--force]                       Delete a contact (dry-run without --force)
contacts-bridge birthdays-today                               Contacts with birthday today
contacts-bridge birthdays-upcoming <days>                     Upcoming birthdays in next N days
```

### notes-bridge
Read and write Apple Notes from Claude Code.

```
notes-bridge accounts                                         List all accounts
notes-bridge folders [account]                                List folders (default: iCloud)
notes-bridge list [folder] [account]                          List notes with modification date
notes-bridge search <query>                                   Search by title and content across all accounts
notes-bridge read <title> [account]                           Read note content as plain text
notes-bridge add <folder> <title> <body> [account]            Create a new note
notes-bridge append <title> <text> [account]                  Append text to an existing note
notes-bridge delete <title> [--force] [account]               Delete a note (dry-run without --force)
```

### mail-bridge
Read and send Apple Mail messages from Claude Code.

```
mail-bridge accounts                                                       List all email accounts
mail-bridge mailboxes [account]                                            List mailboxes (default: first account)
mail-bridge list [mailbox] [account] [count]                               List recent messages (default: INBOX, 20)
mail-bridge unread [mailbox] [account]                                     List unread messages (default: INBOX)
mail-bridge search <query> [account]                                       Search subject/sender in INBOX
mail-bridge read <index> [mailbox] [account]                               Read message by index (marks as read)
mail-bridge send <to> <subject> <body> [/attachment] [--from <email>]      Preview email (dry-run without --force)
mail-bridge send <to> <subject> <body> [/attachment] [--from <email>] --force  Send the email
mail-bridge delete <index> [mailbox] [account] [--force]                   Move to Trash (dry-run without --force)
```

### tmux-bridge
Read tmux session contents from Claude Code — great for end-of-day summaries.

```
tmux-bridge sessions                         List all running sessions
tmux-bridge windows [session]                List windows in a session
tmux-bridge panes [session]                  List all panes with path and command
tmux-bridge read <target> [lines]            Read pane content (e.g. main:1.1, default: 1000 lines)
tmux-bridge snapshot [session] [lines]       Capture all panes at once (default: 5000 lines)
```

Typical workflow: run your work in named tmux sessions, then ask Claude at the end of the day:
> *"Read tmux-bridge snapshot and summarize what I worked on today."*

---

## Setup

### 1. Compile

```bash
# Install all bridges at once (recommended)
git clone https://github.com/more-io/claude-apple-bridges.git
cd claude-apple-bridges
make install
```

Or install individually:

```bash
make install-reminders
make install-calendar
make install-contacts
make install-notes
make install-mail
```

<details>
<summary>Manual compile (without make)</summary>

```bash
# reminders-bridge
cat > /tmp/reminders-info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSRemindersUsageDescription</key>
    <string>Claude Code needs access to Reminders to manage tasks.</string>
</dict>
</plist>
EOF
swiftc reminders-bridge.swift -o ~/.claude/reminders-bridge \
  -framework EventKit \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker /tmp/reminders-info.plist
codesign --force --sign - --identifier com.claude.reminders-bridge ~/.claude/reminders-bridge

# contacts-bridge
cat > /tmp/contacts-info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSContactsUsageDescription</key>
    <string>Claude Code needs access to Contacts to look up and manage contacts.</string>
</dict>
</plist>
EOF
swiftc contacts-bridge.swift -o ~/.claude/contacts-bridge \
  -framework Contacts \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker /tmp/contacts-info.plist
codesign --force --sign - --identifier com.claude.contacts-bridge ~/.claude/contacts-bridge

# calendar-bridge
cat > /tmp/calendar-info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Claude Code needs access to Calendar to schedule and view events.</string>
</dict>
</plist>
EOF
swiftc calendar-bridge.swift -o ~/.claude/calendar-bridge \
  -framework EventKit \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker /tmp/calendar-info.plist
codesign --force --sign - --identifier com.claude.calendar-bridge ~/.claude/calendar-bridge

# notes-bridge
swiftc notes-bridge.swift -o ~/.claude/notes-bridge
codesign --force --sign - --identifier com.claude.notes-bridge ~/.claude/notes-bridge

# mail-bridge
swiftc mail-bridge.swift -o ~/.claude/mail-bridge
codesign --force --sign - --identifier com.claude.mail-bridge ~/.claude/mail-bridge
```

</details>

### 2. Grant permissions

Run each binary once from Terminal to trigger the macOS permission dialog:

```bash
~/.claude/reminders-bridge lists
~/.claude/calendar-bridge today
~/.claude/contacts-bridge search "test"
~/.claude/notes-bridge accounts
~/.claude/mail-bridge accounts
```

Then approve in **System Settings → Privacy & Security → Reminders / Calendars / Contacts / Automation**. Notes and Mail access is granted automatically via AppleScript on first use.

### 3. Add to Claude Code allowed tools

In your project's `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(~/.claude/reminders-bridge:*)",
      "Bash(~/.claude/calendar-bridge:*)",
      "Bash(~/.claude/contacts-bridge:*)",
      "Bash(~/.claude/notes-bridge:*)",
      "Bash(~/.claude/mail-bridge:*)"
    ]
  }
}
```

---

## Requirements

- macOS 13+
- Swift (comes with Xcode or `xcode-select --install`)
- Claude Code

---

## Testing

After installing, run the integration test suite to verify everything works:

```bash
make test
```

35 tests cover all commands across all three bridges — exit codes, output validation, and argument handling. No data is modified during tests.

---

## Contributing

Pull requests are welcome! When adding a new bridge:

1. Create `<name>-bridge.swift` in the repo root
2. Add compile instructions to `README.md` and `CLAUDE.md`
3. Add the permission grant step to `README.md`
4. Add usage examples to `README.md`

See `CLAUDE.md` for developer notes and the branching workflow.

---

## License

MIT — see [LICENSE](LICENSE) for details.
