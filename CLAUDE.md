# Claude Apple Bridges — Developer Notes

## Compile All Bridges

```bash
# Reminders
cat > /tmp/reminders-info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>NSRemindersFullAccessUsageDescription</key>
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

# Notes (no plist needed)
swiftc notes-bridge.swift -o ~/.claude/notes-bridge
codesign --force --sign - --identifier com.claude.notes-bridge ~/.claude/notes-bridge

# Mail (no plist needed)
swiftc mail-bridge.swift -o ~/.claude/mail-bridge
codesign --force --sign - --identifier com.claude.mail-bridge ~/.claude/mail-bridge

# tmux (no plist needed)
swiftc tmux-bridge.swift -o ~/.claude/tmux-bridge
codesign --force --sign - --identifier com.claude.tmux-bridge ~/.claude/tmux-bridge

# Messages
cat > /tmp/messages-info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>NSContactsUsageDescription</key>
    <string>Claude Code needs access to Contacts to show sender names for messages.</string>
</dict></plist>
EOF
swiftc -O messages-bridge.swift -o ~/.claude/messages-bridge -framework Contacts -lsqlite3 \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker /tmp/messages-info.plist
codesign --force --sign - --identifier com.claude.messages-bridge ~/.claude/messages-bridge
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
~/.claude/notes-bridge accounts
~/.claude/mail-bridge accounts
~/.claude/tmux-bridge sessions
~/.claude/messages-bridge chats 5
```

## Branching

- `main` — stable releases
- `develop` — active development, PRs go here

## notes-bridge: HTML Formatting

The `add` and `append` commands support HTML — Notes.app renders it natively:

```bash
notes-bridge add "Work" "Title" "<b>Bold</b><br><ul><li>Item 1</li><li>Item 2</li></ul>"
notes-bridge append "Title" "<br><b>Update:</b> some text"
```

Supported tags: `<b>`, `<i>`, `<u>`, `<br>`, `<ul>`, `<ol>`, `<li>`, `<h1>`–`<h3>`, `<a href="...">`, `<p>`

`read` always returns plain text (HTML stripped).

## mail-bridge: Send Behavior

- **Without `--force`**: opens Mail.app compose window — user reviews and sends manually
- **With `--force`**: sends directly without UI (use only when explicitly requested)

## messages-bridge: Reading chat.db

`chat.db` is opened read-only (`?mode=ro`) and never written to. Two traps live in
that schema — both are handled in the bridge, and both will bite anyone writing
an ad-hoc query against it:

- **The body is frequently NOT in the `text` column.** Newer messages are stored
  as an archived `NSAttributedString` (NSArchiver *typedstream*) in
  `attributedBody`, with `text` left empty — about 25% of rows on a normal Mac.
  Layout after the `NSString` class marker: byte `0x2B`, then a length, then that
  many UTF-8 bytes. The length is a single byte when < `0x80`, otherwise `0x81`
  followed by a UInt16 LE (or `0x82` + UInt32 LE). Verified against 400 rows
  carrying both columns: all decoded byte-identical to `text`.
- **Timestamps are nanoseconds since 2001-01-01**, not Unix seconds; older rows
  use plain seconds. The bridge tells them apart by magnitude.

Also note `item_type`: only `0` is a real message. Other values are system rows
(participant changes, location shares) that carry no body but *do* carry an
unread flag — counting them makes an unread total that no command can ever
show as a message.

## messages-bridge: Send Behavior

`send` delivers immediately via AppleScript — iMessage first, SMS as fallback.
There is no dry-run and no `--force`; any confirmation rule belongs in the
calling Claude instructions.

If sending fails with `AppleEvent timed out (-1712)`, Messages.app's scripting
interface is wedged rather than missing. The giveaway is that even
`tell application "Messages" to get name of every account` hangs. Quitting and
reopening Messages.app fixes it immediately — no code change involved.

## Adding a New Bridge

1. Create `<name>-bridge.swift` in repo root
2. Add compile instructions to README.md and CLAUDE.md
3. Add permission grant step to README.md
4. Add to `settings.local.json` allowed tools
5. Add usage examples to README.md
