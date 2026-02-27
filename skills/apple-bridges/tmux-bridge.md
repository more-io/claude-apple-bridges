# tmux-bridge

Read tmux session contents from Claude Code. Great for end-of-day summaries and capturing terminal output.

**Binary:** `~/.claude/tmux-bridge`

**Requires:** tmux installed and running (`brew install tmux`)

## Commands

### sessions

List all running tmux sessions.

```bash
~/.claude/tmux-bridge sessions
```

Output example:

```
Sessions (2):
  main  windows:3  created:Thu Feb 27 10:00:00 2026  (attached)
  server  windows:1  created:Thu Feb 27 09:00:00 2026
```

### windows

List windows in a session.

```bash
~/.claude/tmux-bridge windows [session]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `session` | No | Session name (default: current session) |

```bash
~/.claude/tmux-bridge windows
~/.claude/tmux-bridge windows "main"
```

Output example:

```
Windows in session 'main':
  0: zsh  [200x50]  1 pane(s) (active)
  1: vim  [200x50]  2 pane(s)
  2: logs  [200x50]  1 pane(s)
```

### panes

List all panes with path and current command.

```bash
~/.claude/tmux-bridge panes [session]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `session` | No | Session name (default: all sessions) |

```bash
~/.claude/tmux-bridge panes
~/.claude/tmux-bridge panes "main"
```

Output example:

```
Panes (4):
  main:0.0  [200x50]  zsh  /Users/tobias/project
  main:1.0  [100x50]  vim  /Users/tobias/project
  main:1.1  [100x50]  zsh  /Users/tobias/project
  main:2.0  [200x50]  tail  /var/log
```

### read

Read content from a specific pane.

```bash
~/.claude/tmux-bridge read <target> [lines]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `target` | Yes | Pane target in `session:window.pane` format (e.g., `main:0.0`) |
| `lines` | No | Number of lines to capture (default: `1000`) |

```bash
~/.claude/tmux-bridge read "main:0.0"
~/.claude/tmux-bridge read "main:1.1" 500
```

**Target format:** `session:window.pane` — use `panes` command to see available targets.

### snapshot

Capture all panes at once. Ideal for end-of-day summaries.

```bash
~/.claude/tmux-bridge snapshot [session] [lines]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `session` | No | Session name (default: all sessions) |
| `lines` | No | Lines per pane to capture (default: `5000`) |

```bash
# All sessions
~/.claude/tmux-bridge snapshot

# Specific session
~/.claude/tmux-bridge snapshot "main"

# With custom line count
~/.claude/tmux-bridge snapshot "main" 2000
```

Output format:

```
=== tmux snapshot: session 'main' ===
Captured: 2026-02-27 18:00:00 +0000

-------------------------------------
Pane: main:0.0  [zsh] zsh @ /Users/tobias/project
-------------------------------------
<pane content>

-------------------------------------
Pane: main:1.0  [vim] vim @ /Users/tobias/project
-------------------------------------
<pane content>
```

## Common Workflows

### End-of-day summary

```bash
~/.claude/tmux-bridge snapshot
```

Then ask Claude: "Summarize what I worked on today based on this tmux snapshot."

### Check a specific terminal

```bash
~/.claude/tmux-bridge panes
~/.claude/tmux-bridge read "main:2.0"
```

### Monitor logs

```bash
~/.claude/tmux-bridge read "server:0.0" 200
```
