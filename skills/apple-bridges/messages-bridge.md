# messages-bridge

Read and send Apple Messages (iMessage / SMS) from Claude Code. Reads the Messages database directly (read-only) and sends through Messages.app.

**Binary:** `~/.claude/messages-bridge`

**Requires:** Full Disk Access for the terminal (to read `~/Library/Messages/chat.db`) and Automation → Messages (to send).

## Commands

### chats

List the most recent conversations, newest first.

```bash
~/.claude/messages-bridge chats [count]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `count` | No | Number of conversations (default: `20`) |

Output example:

```
1. [2026-09-04 09:08] Anna Muller <+491701234567> [2 unread] — See you at eight
2. [2026-09-03 17:09] Family <chat957280819354874144> — Me: Bringing dessert
3. [2026-09-01 15:43] Ben Weber <ben@example.com> — let's align tomorrow
```

The angle brackets show the identifier you can pass to `list` and `read`.

### unread

List unread incoming messages.

```bash
~/.claude/messages-bridge unread [count]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `count` | No | Number of messages (default: `20`) |

Only real messages are counted. Messages keeps system rows (participant changes, location shares) in the same table with an unread flag and no body — those are excluded, so this command and the `[n unread]` marker in `chats` always agree.

### list

List the messages of one conversation, oldest first so the thread reads naturally.

```bash
~/.claude/messages-bridge list <chat|handle> [count]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `chat\|handle` | Yes | Phone number, email address, group name, chat identifier, or contact name |
| `count` | No | Number of messages (default: `20`) |

```bash
~/.claude/messages-bridge list "+491701234567"
~/.claude/messages-bridge list "Anna Muller" 50
~/.claude/messages-bridge list "Family"
```

Output example:

```
1. [2026-09-04 08:47] Anna Muller: Are we still on for tonight?
2. [2026-09-04 09:08] Me: Yes — eight o'clock
```

### search

Search the text of all messages, newest first.

```bash
~/.claude/messages-bridge search <query> [count]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `query` | Yes | Case-insensitive substring |
| `count` | No | Number of hits (default: `20`) |

```bash
~/.claude/messages-bridge search "invoice"
~/.claude/messages-bridge search "dinner" 5
```

This searches decoded bodies, not just the `text` column — see *How reading works* below. A plain SQL query against `chat.db` would miss about a quarter of all messages.

### read

Same selection as `list`, but prints each message in full instead of truncating it to one line. Use it when you actually need the content.

```bash
~/.claude/messages-bridge read <chat|handle> [count]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `chat\|handle` | Yes | Same as `list` |
| `count` | No | Number of messages (default: `10`) |

### send

Send a message. Tries iMessage first and falls back to SMS.

```bash
~/.claude/messages-bridge send <handle> <text>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `handle` | Yes | Phone number, email address, or a contact name that resolves to exactly one address |
| `text` | Yes | Message body |

```bash
~/.claude/messages-bridge send "+491701234567" "On my way"
~/.claude/messages-bridge send "ben@example.com" "Sending the file now"
~/.claude/messages-bridge send "Anna Muller" "Running ten minutes late"
```

A contact name is only accepted when it maps to a single address; if the contact has several, the bridge lists them and exits rather than guessing.

> **`send` delivers immediately and asks nothing.** There is no dry-run and no confirmation flag. If you want Claude to confirm before messaging someone, put that rule in your Claude Code instructions — deliberately not in the tool.

## How reading works

The bridge opens `~/Library/Messages/chat.db` read-only and never writes to it.

Two properties of that database are worth knowing, because both are handled here and both bite anyone querying it by hand:

- **The body is often not in the `text` column.** Apple stores newer messages as an archived `NSAttributedString` (an NSArchiver *typedstream*) in `attributedBody` and leaves `text` empty — roughly a quarter of all rows on a normal Mac. The bridge decodes that stream, so those messages are not silently blank. A `SELECT ... WHERE text LIKE ...` will not find them.
- **Timestamps are nanoseconds since 2001-01-01,** not Unix seconds. Older rows use plain seconds; the bridge handles both.

Sender names are resolved through Contacts. Without Contacts permission everything still works — you just see raw phone numbers and email addresses instead of names.

## Common Workflows

### Catch up on what came in

```bash
~/.claude/messages-bridge unread
```

Then ask Claude: "Summarize my unread messages and tell me which ones need an answer today."

### Find an old detail

```bash
~/.claude/messages-bridge search "address"
```

### Read a thread before replying

```bash
~/.claude/messages-bridge read "Anna Muller" 20
~/.claude/messages-bridge send "Anna Muller" "Sorry for the delay — yes, that works."
```

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| `Error: cannot open the Messages database` | The terminal lacks Full Disk Access. Grant it in System Settings → Privacy & Security → Full Disk Access, then **restart the terminal** — the grant only applies to newly started processes. |
| `send` fails with `AppleEvent timed out (-1712)` | Messages.app's scripting interface is wedged. Quit Messages.app and reopen it; sending works again immediately. A telltale sign is that even a trivial script like `tell application "Messages" to get name of every account` hangs. |
| Names show as raw phone numbers | No Contacts permission. Run any command once from Terminal and approve the prompt, or grant it under Privacy & Security → Contacts. |
| A message shows as `￼` | That row is an attachment (image, link preview) with no text body. |
