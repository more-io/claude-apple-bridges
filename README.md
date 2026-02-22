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

## Requirements

- macOS 13+
- Swift (comes with Xcode or `xcode-select --install`)
- Claude Code
