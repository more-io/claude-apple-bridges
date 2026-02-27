# reminders-bridge

Manage Apple Reminders from Claude Code via EventKit.

**Binary:** `~/.claude/reminders-bridge`

## Commands

### lists

List all reminder lists.

```bash
~/.claude/reminders-bridge lists
```

### create-list

Create a new reminder list.

```bash
~/.claude/reminders-bridge create-list <listName>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `listName` | Yes | Name for the new list |

```bash
~/.claude/reminders-bridge create-list "Project Ideas"
```

### items

Show all reminders in a list (completed and incomplete).

```bash
~/.claude/reminders-bridge items <listName>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `listName` | Yes | Name of the reminder list |

### incomplete

Show only incomplete reminders in a list.

```bash
~/.claude/reminders-bridge incomplete <listName>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `listName` | Yes | Name of the reminder list |

### today

Show reminders due today across all lists.

```bash
~/.claude/reminders-bridge today
```

### overdue

Show all overdue reminders across all lists.

```bash
~/.claude/reminders-bridge overdue
```

### search

Search reminders by title and notes across all lists.

```bash
~/.claude/reminders-bridge search <query>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `query` | Yes | Search term (case-insensitive, matches title and notes) |

```bash
~/.claude/reminders-bridge search "PR review"
```

### add

Add a new reminder to a list.

```bash
~/.claude/reminders-bridge add <listName> <title> [notes]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `listName` | Yes | Target reminder list |
| `title` | Yes | Reminder title |
| `notes` | No | Additional notes |

```bash
# Without notes
~/.claude/reminders-bridge add "Work" "Review PR #42"

# With notes
~/.claude/reminders-bridge add "Work" "Review PR #42" "Focus on auth changes in src/login.swift"
```

### set-due

Set or update the due date of a reminder.

```bash
~/.claude/reminders-bridge set-due <listName> <title> <datetime>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `listName` | Yes | Reminder list name |
| `title` | Yes | Reminder title (must be incomplete) |
| `datetime` | Yes | Due date in `YYYY-MM-DD HH:mm` format |

```bash
~/.claude/reminders-bridge set-due "Work" "Review PR #42" "2026-03-01 09:00"
```

### set-notes

Set or update the notes of a reminder.

```bash
~/.claude/reminders-bridge set-notes <listName> <title> <notes>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `listName` | Yes | Reminder list name |
| `title` | Yes | Reminder title (must be incomplete) |
| `notes` | Yes | New notes content |

```bash
~/.claude/reminders-bridge set-notes "Work" "Review PR #42" "Updated: also check the migration script"
```

### complete

Mark a reminder as complete.

```bash
~/.claude/reminders-bridge complete <listName> <title>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `listName` | Yes | Reminder list name |
| `title` | Yes | Reminder title (must be incomplete) |

```bash
~/.claude/reminders-bridge complete "Work" "Review PR #42"
```

### delete

Delete a reminder. Dry-run by default — use `--force` to actually delete.

```bash
~/.claude/reminders-bridge delete <listName> <title> [--force]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `listName` | Yes | Reminder list name |
| `title` | Yes | Reminder title |
| `--force` | No | Actually delete (without: dry-run preview) |

```bash
# Preview what would be deleted
~/.claude/reminders-bridge delete "Work" "Old task"

# Actually delete
~/.claude/reminders-bridge delete "Work" "Old task" --force
```

## Output Format

Reminders are displayed as:

```
[x] Buy groceries! (due: 01.03.26, 09:00) [repeats: weekly] [Shopping]
     Notes: Organic milk and sourdough bread
```

- `[x]` = completed, `[ ]` = incomplete
- `!!` = high priority, `!` = medium priority
- Due date shown if set
- Recurrence shown if set
- List name in brackets
- Notes on next line if present

## Common Workflows

### Track a coding task

```bash
~/.claude/reminders-bridge add "4later" "Implement MCP server" "GitHub issue #15, feature/mcp-server branch"
~/.claude/reminders-bridge set-due "4later" "Implement MCP server" "2026-03-05 10:00"
```

### Check what's due and overdue

```bash
~/.claude/reminders-bridge today
~/.claude/reminders-bridge overdue
```

### Complete a task after finishing work

```bash
~/.claude/reminders-bridge complete "4later" "Implement MCP server"
```
