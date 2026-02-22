# Claude Apple Bridges

Swift CLI tools that give [Claude Code](https://claude.ai/claude-code) access to Apple native apps via EventKit. Designed to be used as allowed tools in Claude Code's `settings.local.json`.

## Bridges

### reminders-bridge
Access and manage Apple Reminders from Claude Code.

```
reminders-bridge lists                              List all reminder lists
reminders-bridge create-list <name>                 Create a new list
reminders-bridge items <list>                       Show all reminders in a list
reminders-bridge incomplete <list>                  Show only incomplete reminders
reminders-bridge add <list> <title> [notes]         Add a new reminder
reminders-bridge set-due <list> <title> <datetime>  Set due date (YYYY-MM-DD HH:mm)
reminders-bridge complete <list> <title>            Mark a reminder as complete
```

### calendar-bridge
Read and write Apple Calendar events from Claude Code.

```
calendar-bridge calendars                                     List all calendars
calendar-bridge today                                         Show today's events
calendar-bridge tomorrow                                      Show tomorrow's events
calendar-bridge events <YYYY-MM-DD>                           Show events for a date
calendar-bridge add <cal> <title> <start> <end>               Add event (YYYY-MM-DD HH:mm)
calendar-bridge add-all-day <cal> <title> <YYYY-MM-DD>        Add all-day event
```

## Setup

### 1. Compile

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
```

### 2. Grant permissions

Run each binary once from Terminal to trigger the macOS permission dialog:

```bash
~/.claude/reminders-bridge lists
~/.claude/calendar-bridge today
```

Then approve in **System Settings → Privacy & Security → Reminders / Calendars**.

### 3. Add to Claude Code allowed tools

In your project's `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(~/.claude/reminders-bridge:*)",
      "Bash(~/.claude/calendar-bridge:*)"
    ]
  }
}
```

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

## Requirements

- macOS 13+
- Swift (comes with Xcode or `xcode-select --install`)
- Claude Code
