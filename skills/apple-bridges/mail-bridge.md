# mail-bridge

Read and send Apple Mail messages from Claude Code via AppleScript.

**Binary:** `~/.claude/mail-bridge`

**Default mailbox:** `INBOX`

## Commands

### accounts

List all email accounts.

```bash
~/.claude/mail-bridge accounts
```

### mailboxes

List mailboxes for an account.

```bash
~/.claude/mail-bridge mailboxes [account]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `account` | No | Account name (default: first account) |

```bash
~/.claude/mail-bridge mailboxes
~/.claude/mail-bridge mailboxes "iCloud"
```

### list

List recent messages. Smart argument detection: if the second argument matches an account name, it's treated as the account (not a mailbox).

```bash
~/.claude/mail-bridge list [mailbox|account] [account] [count]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `mailbox` | No | Mailbox name (default: `INBOX`) |
| `account` | No | Account name (default: first account) |
| `count` | No | Number of messages to show (default: `20`) |

```bash
# Default: 20 most recent in INBOX
~/.claude/mail-bridge list

# Specific mailbox
~/.claude/mail-bridge list "Sent Messages"

# Account shortcut (auto-detected)
~/.claude/mail-bridge list "iCloud"

# Mailbox + account + count
~/.claude/mail-bridge list "INBOX" "iCloud" 50
```

Output format: `<index>. <subject> [UNREAD] — <sender> (<month>/<day>)`

### unread

List unread messages. Same smart argument detection as `list`.

```bash
~/.claude/mail-bridge unread [mailbox|account] [account]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `mailbox` | No | Mailbox name (default: `INBOX`) |
| `account` | No | Account name (default: first account) |

```bash
~/.claude/mail-bridge unread
~/.claude/mail-bridge unread "iCloud"
~/.claude/mail-bridge unread "INBOX" "iCloud"
```

### search

Search messages by subject and sender in INBOX.

```bash
~/.claude/mail-bridge search <query> [account]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `query` | Yes | Search term (matches subject and sender) |
| `account` | No | Account name (default: first account) |

```bash
~/.claude/mail-bridge search "invoice"
~/.claude/mail-bridge search "invoice" "iCloud"
```

### read

Read a message by its index number (from `list` output). Unread status is preserved by default.

```bash
~/.claude/mail-bridge read <index> [mailbox] [account] [--mark-read]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `index` | Yes | Message index (from `list` output) |
| `mailbox` | No | Mailbox name (default: `INBOX`) |
| `account` | No | Account name (default: first account) |
| `--mark-read` | No | Mark message as read after reading |

```bash
# Read without changing status
~/.claude/mail-bridge read 1

# Read and mark as read
~/.claude/mail-bridge read 3 --mark-read

# Specific mailbox
~/.claude/mail-bridge read 1 "Sent Messages" "iCloud"
```

### send

Compose and send an email. **Without `--force`**: opens a compose window in Mail.app for review. **With `--force`**: sends directly without UI.

```bash
~/.claude/mail-bridge send <to> <subject> <body> [/path/to/attachment] [--from <email>] [--force]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `to` | Yes | Recipient email address |
| `subject` | Yes | Email subject |
| `body` | Yes | Email body text |
| `/path/to/attachment` | No | Path to file attachment |
| `--from <email>` | No | Sender email address (default: first account's email) |
| `--force` | No | Send directly without opening compose window |

```bash
# Open compose window for review (recommended)
~/.claude/mail-bridge send "heiko@web.de" "Meeting Notes" "Hi Heiko, here are the notes..."

# Send directly (use with care)
~/.claude/mail-bridge send "heiko@web.de" "Meeting Notes" "Hi Heiko, here are the notes..." --force

# With attachment and specific sender
~/.claude/mail-bridge send "heiko@web.de" "Report" "See attached." /tmp/report.pdf --from work@company.com

# All options
~/.claude/mail-bridge send "heiko@web.de" "Report" "See attached." /tmp/report.pdf --from work@company.com --force
```

**Important:** Always prefer opening the compose window (without `--force`) unless the user explicitly asks to send directly.

### delete

Move a message to Trash. Dry-run by default — use `--force` to actually delete.

```bash
~/.claude/mail-bridge delete <index> [mailbox] [account] [--force]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `index` | Yes | Message index |
| `mailbox` | No | Mailbox name (default: `INBOX`) |
| `account` | No | Account name (default: first account) |
| `--force` | No | Actually move to Trash (without: dry-run preview) |

```bash
# Preview
~/.claude/mail-bridge delete 5

# Actually delete
~/.claude/mail-bridge delete 5 --force
```

## Common Workflows

### Check for new mail

```bash
~/.claude/mail-bridge unread
~/.claude/mail-bridge read 1
```

### Draft a reply

```bash
# Read the original message
~/.claude/mail-bridge read 3 --mark-read

# Compose a reply (opens in Mail.app for review)
~/.claude/mail-bridge send "sender@example.com" "Re: Original Subject" "Thanks for your message..."
```

### Search and read

```bash
~/.claude/mail-bridge search "quarterly report"
~/.claude/mail-bridge read 1
```
