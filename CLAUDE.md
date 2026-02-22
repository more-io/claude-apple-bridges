# Claude Apple Bridges — Developer Notes

## Compile All Bridges

```bash
# Reminders
cat > /tmp/reminders-info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>NSRemindersUsageDescription</key>
    <string>Claude Code needs access to Reminders to manage tasks.</string>
</dict></plist>
EOF
swiftc reminders-bridge.swift -o ~/.claude/reminders-bridge -framework EventKit \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker /tmp/reminders-info.plist
codesign --force --sign - --identifier com.claude.reminders-bridge ~/.claude/reminders-bridge

# Contacts
cat > /tmp/contacts-info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>NSContactsUsageDescription</key>
    <string>Claude Code needs access to Contacts.</string>
</dict></plist>
EOF
swiftc contacts-bridge.swift -o ~/.claude/contacts-bridge -framework Contacts \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker /tmp/contacts-info.plist
codesign --force --sign - --identifier com.claude.contacts-bridge ~/.claude/contacts-bridge

# Calendar
cat > /tmp/calendar-info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Claude Code needs access to Calendar.</string>
</dict></plist>
EOF
swiftc calendar-bridge.swift -o ~/.claude/calendar-bridge -framework EventKit \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker /tmp/calendar-info.plist
codesign --force --sign - --identifier com.claude.calendar-bridge ~/.claude/calendar-bridge
```

## Quick Smoke Test

```bash
~/.claude/reminders-bridge lists
~/.claude/reminders-bridge today
~/.claude/reminders-bridge overdue
~/.claude/calendar-bridge today
~/.claude/calendar-bridge free-slots $(date +%Y-%m-%d)
~/.claude/contacts-bridge search "test"
~/.claude/contacts-bridge birthdays-upcoming 30
```

## Branching

- `main` — stable releases
- `develop` — active development, PRs go here

## Adding a New Bridge

1. Create `<name>-bridge.swift` in repo root
2. Add compile instructions to README.md and CLAUDE.md
3. Add permission grant step to README.md
4. Add to `settings.local.json` allowed tools
5. Add usage examples to README.md
