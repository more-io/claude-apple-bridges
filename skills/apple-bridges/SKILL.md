---
name: apple-bridges
description: Use this skill whenever the user asks about Apple apps — Reminders, Calendar, Contacts, Notes, Mail, or tmux sessions. This includes creating/completing reminders, checking/adding calendar events, looking up contacts, reading/writing notes, sending/reading email, and capturing tmux session content. Also use this skill when the user mentions tasks, todos, scheduling, birthdays, free time slots, or end-of-day summaries. The bridges are CLI tools installed at ~/.claude/ that give Claude Code native access to these Apple apps on macOS.
---

# Apple Bridges

Swift CLI tools at `~/.claude/` that give Claude Code native access to Apple apps on macOS.

## Quick Reference

| Bridge | Binary | Purpose |
|--------|--------|---------|
| [reminders-bridge](reminders-bridge.md) | `~/.claude/reminders-bridge` | Manage Apple Reminders — lists, items, due dates, search |
| [calendar-bridge](calendar-bridge.md) | `~/.claude/calendar-bridge` | Read/write Apple Calendar — events, free slots, scheduling |
| [contacts-bridge](contacts-bridge.md) | `~/.claude/contacts-bridge` | Search/manage Apple Contacts — lookup, birthdays |
| [notes-bridge](notes-bridge.md) | `~/.claude/notes-bridge` | Read/write Apple Notes — create, search, append |
| [mail-bridge](mail-bridge.md) | `~/.claude/mail-bridge` | Read/send Apple Mail — inbox, unread, compose |
| [tmux-bridge](tmux-bridge.md) | `~/.claude/tmux-bridge` | Read tmux sessions — panes, snapshots |

**Read the detail file for the bridge you need** — each contains full command syntax, all parameters, and usage examples.

## General Patterns

### CLI Syntax

All bridges follow the same pattern:

```bash
~/.claude/<bridge-name> <command> [arguments...]
```

### Quoting

Arguments with spaces must be quoted:

```bash
~/.claude/reminders-bridge add "Shopping List" "Buy milk" "From the organic store"
~/.claude/calendar-bridge add "Work" "Team Meeting" "2026-03-01 10:00" "2026-03-01 11:00"
```

### Destructive Operations

Delete commands use a **dry-run by default** pattern — they show what would be deleted without the `--force` flag:

```bash
# Dry run (safe preview)
~/.claude/reminders-bridge delete "Work" "Old task"

# Actually delete
~/.claude/reminders-bridge delete "Work" "Old task" --force
```

This applies to: `reminders-bridge delete`, `calendar-bridge delete`, `contacts-bridge delete`, `notes-bridge delete`, `mail-bridge delete`.

### Permissions

Each bridge requires macOS permission on first use:

| Bridge | Permission | Settings Path |
|--------|-----------|---------------|
| reminders-bridge | Reminders | Privacy & Security > Reminders |
| calendar-bridge | Calendars | Privacy & Security > Calendars |
| contacts-bridge | Contacts | Privacy & Security > Contacts |
| notes-bridge | Automation (Notes.app) | Privacy & Security > Automation |
| mail-bridge | Automation (Mail.app) | Privacy & Security > Automation |
| tmux-bridge | None (uses tmux CLI) | — |

### Allowed Tools Configuration

Add to `.claude/settings.local.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(~/.claude/reminders-bridge:*)",
      "Bash(~/.claude/calendar-bridge:*)",
      "Bash(~/.claude/contacts-bridge:*)",
      "Bash(~/.claude/notes-bridge:*)",
      "Bash(~/.claude/mail-bridge:*)",
      "Bash(~/.claude/tmux-bridge:*)"
    ]
  }
}
```
