# calendar-bridge

Read and write Apple Calendar events from Claude Code via EventKit.

**Binary:** `~/.claude/calendar-bridge`

## Commands

### calendars

List all calendars. Read-only calendars are marked.

```bash
~/.claude/calendar-bridge calendars
```

Output example:

```
Home
Work
Birthdays (read-only)
```

### today

Show today's events across all calendars.

```bash
~/.claude/calendar-bridge today
```

### tomorrow

Show tomorrow's events across all calendars.

```bash
~/.claude/calendar-bridge tomorrow
```

### week

Show all events for the current week (Monday through Sunday).

```bash
~/.claude/calendar-bridge week
```

### events

Show events for a specific date.

```bash
~/.claude/calendar-bridge events <YYYY-MM-DD>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `YYYY-MM-DD` | Yes | Date to show events for |

```bash
~/.claude/calendar-bridge events 2026-03-15
```

### free-slots

Show free time slots for a specific date. Working hours: 08:00-20:00, minimum slot: 30 minutes.

```bash
~/.claude/calendar-bridge free-slots <YYYY-MM-DD>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `YYYY-MM-DD` | Yes | Date to find free slots for |

```bash
~/.claude/calendar-bridge free-slots 2026-03-01
```

Output example:

```
Free slots on Sonntag, 01. März 2026:
  08:00 – 10:00  (120 min)
  11:30 – 13:00  (90 min)
  15:00 – 20:00  (300 min)
```

### search

Search events by title in the next 365 days.

```bash
~/.claude/calendar-bridge search <query>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `query` | Yes | Search term (case-insensitive, matches title) |

```bash
~/.claude/calendar-bridge search "standup"
```

### add

Add a timed event to a calendar.

```bash
~/.claude/calendar-bridge add <calendar> <title> <start> <end>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `calendar` | Yes | Calendar name (must not be read-only) |
| `title` | Yes | Event title |
| `start` | Yes | Start time in `YYYY-MM-DD HH:mm` format |
| `end` | Yes | End time in `YYYY-MM-DD HH:mm` format |

```bash
~/.claude/calendar-bridge add "Work" "Code Review" "2026-03-01 14:00" "2026-03-01 15:00"
```

### add-all-day

Add an all-day event to a calendar.

```bash
~/.claude/calendar-bridge add-all-day <calendar> <title> <YYYY-MM-DD>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `calendar` | Yes | Calendar name (must not be read-only) |
| `title` | Yes | Event title |
| `YYYY-MM-DD` | Yes | Date for the all-day event |

```bash
~/.claude/calendar-bridge add-all-day "Work" "Release Day" 2026-03-15
```

### delete

Delete an event. Dry-run by default — use `--force` to actually delete.

```bash
~/.claude/calendar-bridge delete <calendar> <title> <YYYY-MM-DD> [--force]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `calendar` | Yes | Calendar name |
| `title` | Yes | Event title (exact match) |
| `YYYY-MM-DD` | Yes | Date of the event |
| `--force` | No | Actually delete (without: dry-run preview) |

```bash
# Preview
~/.claude/calendar-bridge delete "Work" "Old Meeting" 2026-03-01

# Actually delete
~/.claude/calendar-bridge delete "Work" "Old Meeting" 2026-03-01 --force
```

## Output Format

Events are displayed as:

```
Events for Montag, 01. März 2026:
  [09:00 – 10:00] Team Standup @ Zoom  (Work)
  [All day] Release Day  (Work)
```

- Time range or "All day" in brackets
- Location shown with `@` if set
- Calendar name in parentheses

## Common Workflows

### Schedule work avoiding conflicts

```bash
# Check what's booked
~/.claude/calendar-bridge tomorrow

# Find free time
~/.claude/calendar-bridge free-slots 2026-03-01

# Book a slot
~/.claude/calendar-bridge add "Work" "Deep Work: MCP Server" "2026-03-01 14:00" "2026-03-01 16:00"
```

### Weekly planning

```bash
~/.claude/calendar-bridge week
```
