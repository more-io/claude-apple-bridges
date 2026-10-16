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

# MCP server for Claude Desktop (no plist needed, optional)
swiftc -O apple-bridges-mcp.swift -o ~/.claude/apple-bridges-mcp
codesign --force --sign - --identifier com.claude.apple-bridges-mcp ~/.claude/apple-bridges-mcp
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
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | ~/.claude/apple-bridges-mcp
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

Signature: `send <handle> <text> [/path/to/attachment ...]`, positional like
mail-bridge. The buddy is resolved once into a variable, then the text is sent
(when non-empty), then one `send POSIX file` per attachment — Messages delivers
each attachment as its own message, which is the app's behaviour, not a choice
here. `""` as the text sends files only. The SMS fallback branch carries the
same body with its own buddy variable.

Paths are expanded (tilde and relative become absolute, which `POSIX file`
requires) and every one is checked for existence and for not being a directory
BEFORE the first send — a typo in the third path must not leave the first two
already delivered, since nothing can unsend them.

**The one place people trip:** `<text>` is a SINGLE argument. Multi-word text
must be quoted, otherwise the extra words are read as file paths and the call
aborts with "attachment not found". This is deliberate — it is what makes
trailing paths unambiguous, and it fails loudly rather than silently
reinterpreting the message.

If sending fails with `AppleEvent timed out (-1712)`, Messages.app's scripting
interface is wedged rather than missing. The giveaway is that even
`tell application "Messages" to get name of every account` hangs. Quitting and
reopening Messages.app fixes it immediately — no code change involved.

## apple-bridges-mcp: MCP Server for Claude Desktop

An stdio MCP server in one file, Foundation only. It implements `initialize`,
`ping`, `tools/list`, and `tools/call`, and nothing else. Each installed bridge
is a `<bridge>_read` and a `<bridge>_write` tool. A tool passes `args` to the
binary unchanged, but only when `args[0]` is a command on its side, so the
bridge CLIs stay the single source of truth for everything else.

- **Read and write are separate tools.** Claude Desktop approves a whole tool,
  so "always allow" on a single tool would cover every command. Each row in
  `bridges` lists its read and its write commands. A command on neither side is
  refused, so a new bridge command stays unreachable until it is classified;
  `test.sh` fails when a usage command is on neither side. Two deliberate
  calls: `mail read --mark-read` stays on the read side, and all of tmux is on
  the write side.
- **Tool descriptions come from the bridges.** `tools/list` runs each bridge
  with no arguments and uses its usage output, cut to the tool's side. A
  wrapped usage line (messages `send`) follows the command line above it. With
  no arguments, every bridge prints usage before requesting EventKit or
  Contacts access, so this never triggers a permission prompt. Keep it that way
  in new bridges. A command with missing arguments may still ask for access
  first (`reminders-bridge search`), so tests that must run without
  permissions use `notes-bridge read`.
- **30-second timeout.** A watchdog sends SIGTERM to the bridge. That ends the
  call because AppleScript runs inside the bridge (`NSAppleScript`); a bridge
  that started a long-lived child holding the pipe would defeat it. Exit by
  SIGTERM is how the server tells a timeout from a crash. A stopped write may
  still take effect (Messages can deliver a queued send later), so the error
  says to check before retrying.
- **No shell.** The bridge runs through `Process` with an argument array, so
  the messages-bridge quoting trap cannot happen here.
- **stdin is `/dev/null` for the bridge.** stdin is the MCP stream; a bridge
  that read it would swallow the client's next request.
- **Drain the pipe before `waitUntilExit()`.** Output larger than the pipe
  buffer (a tmux snapshot) otherwise blocks the bridge forever.
- **Bridges are found next to the server binary**, not at a hardcoded
  `~/.claude`, so `INSTALL_DIR` overrides keep working.
- **stdout carries only JSON-RPC.** Never `print()` in the server; one stray
  line breaks the client.
- **macOS attributes permissions to `apple-bridges-mcp`, not Claude.app.**
  Claude Desktop appears to launch the server as its own responsible process:
  the Mail Automation prompt names `apple-bridges-mcp`. Grants follow the server's
  code signature: an ad-hoc rebuild can reset them, and Full Disk Access for
  messages-bridge must be added to the server binary by hand.

## Adding a New Bridge

1. Create `<name>-bridge.swift` in repo root
2. Add compile instructions to README.md and CLAUDE.md
3. Add permission grant step to README.md
4. Add to `settings.local.json` allowed tools
5. Add usage examples to README.md
6. Add the bridge to the `bridges` list in `apple-bridges-mcp.swift`, with
   every command on the read or the write side. A new command for an existing
   bridge goes on a side there too.
