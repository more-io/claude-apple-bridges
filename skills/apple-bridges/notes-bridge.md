# notes-bridge

Read and write Apple Notes from Claude Code via AppleScript.

**Binary:** `~/.claude/notes-bridge`

**Default account:** `iCloud`
**Default folder:** `Notes`

## Commands

### accounts

List all Notes accounts.

```bash
~/.claude/notes-bridge accounts
```

### folders

List folders in an account.

```bash
~/.claude/notes-bridge folders [account]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `account` | No | Account name (default: `iCloud`) |

```bash
~/.claude/notes-bridge folders
~/.claude/notes-bridge folders "Gmail"
```

### list

List notes in a folder with modification dates.

```bash
~/.claude/notes-bridge list [folder] [account]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `folder` | No | Folder name (default: `Notes`) |
| `account` | No | Account name (default: `iCloud`) |

```bash
~/.claude/notes-bridge list
~/.claude/notes-bridge list "Work"
~/.claude/notes-bridge list "Work" "iCloud"
```

Output example:

```
Meeting Notes  [2026-03-01]
Project Ideas  [2026-02-28]
```

### search

Search notes by title and content across all accounts.

```bash
~/.claude/notes-bridge search <query>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `query` | Yes | Search term (matches title and body) |

```bash
~/.claude/notes-bridge search "architecture"
```

### read

Read a note's content as plain text (HTML stripped).

```bash
~/.claude/notes-bridge read <title> [account]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `title` | Yes | Exact note title |
| `account` | No | Account name (default: searches all accounts) |

```bash
~/.claude/notes-bridge read "Meeting Notes"
~/.claude/notes-bridge read "Meeting Notes" "iCloud"
```

### add

Create a new note. Supports HTML formatting.

```bash
~/.claude/notes-bridge add <folder> <title> <body> [account]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `folder` | Yes | Target folder |
| `title` | Yes | Note title |
| `body` | Yes | Note body (plain text or HTML) |
| `account` | No | Account name (default: `iCloud`) |

```bash
# Plain text
~/.claude/notes-bridge add "Notes" "Shopping" "Milk, Bread, Eggs"

# HTML formatted
~/.claude/notes-bridge add "Work" "Meeting Notes" "<b>Attendees:</b> Tobias, Heiko<br><br><ul><li>Discussed roadmap</li><li>Next: review PR</li></ul>"
```

**Supported HTML tags:** `<b>`, `<i>`, `<u>`, `<br>`, `<ul>`, `<ol>`, `<li>`, `<h1>`-`<h3>`, `<a href="...">`, `<p>`

### append

Append text to an existing note. Supports HTML.

```bash
~/.claude/notes-bridge append <title> <text> [account]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `title` | Yes | Exact note title |
| `text` | Yes | Text to append (plain or HTML) |
| `account` | No | Account name (default: searches all accounts) |

```bash
~/.claude/notes-bridge append "Meeting Notes" "Follow-up: send report by Friday"
~/.claude/notes-bridge append "Meeting Notes" "<br><b>Update:</b> deadline extended to Monday"
```

### delete

Delete a note. Dry-run by default — use `--force` to actually delete.

```bash
~/.claude/notes-bridge delete <title> [--force] [account]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `title` | Yes | Exact note title |
| `--force` | No | Actually delete (without: dry-run preview) |
| `account` | No | Account name (default: searches all accounts) |

```bash
# Preview
~/.claude/notes-bridge delete "Old Note"

# Actually delete
~/.claude/notes-bridge delete "Old Note" --force
```

## Common Workflows

### Session notes

```bash
# Create a note for today's session
~/.claude/notes-bridge add "Work" "Dev Session 2026-03-01" "<b>Goal:</b> Implement MCP server<br><ul><li>Created SKILL.md</li><li>Updated README</li></ul>"

# Append as work progresses
~/.claude/notes-bridge append "Dev Session 2026-03-01" "<br><b>Completed:</b> All skill files created and tested"
```

### Search and read

```bash
~/.claude/notes-bridge search "MCP"
~/.claude/notes-bridge read "MCP Server Design"
```
