# contacts-bridge

Search and manage Apple Contacts from Claude Code via the Contacts framework.

**Binary:** `~/.claude/contacts-bridge`

## Commands

### search

Search contacts by name, email, or phone.

```bash
~/.claude/contacts-bridge search <query>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `query` | Yes | Name to search for |

```bash
~/.claude/contacts-bridge search "Thomas"
```

Output shows name, organization, phone numbers, and email addresses.

### show

Show full details for a contact, including address, birthday, and notes.

```bash
~/.claude/contacts-bridge show <name>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `name` | Yes | Contact name to look up |

```bash
~/.claude/contacts-bridge show "Thomas Müller"
```

### add

Add a new contact.

```bash
~/.claude/contacts-bridge add <firstName> <lastName> [phone] [email]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `firstName` | Yes | First name |
| `lastName` | Yes | Last name |
| `phone` | No | Phone number (saved as mobile) |
| `email` | No | Email address (saved as work) |

```bash
# Name only
~/.claude/contacts-bridge add "Alex" "Schmidt"

# With phone and email
~/.claude/contacts-bridge add "Alex" "Schmidt" "+49 123 456789" "alex@example.com"
```

### update

Update a contact's phone or email.

```bash
~/.claude/contacts-bridge update <name> phone <value>
~/.claude/contacts-bridge update <name> email <value>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `name` | Yes | Contact name |
| `phone`/`email` | Yes | Field to update |
| `value` | Yes | New value |

```bash
~/.claude/contacts-bridge update "Alex Schmidt" phone "+49 987 654321"
~/.claude/contacts-bridge update "Alex Schmidt" email "alex.new@example.com"
```

**Note:** Update replaces the existing phone/email — it does not append.

### delete

Delete a contact. Dry-run by default — use `--force` to actually delete.

```bash
~/.claude/contacts-bridge delete <name> [--force]
```

| Argument | Required | Description |
|----------|----------|-------------|
| `name` | Yes | Contact name |
| `--force` | No | Actually delete (without: dry-run preview) |

```bash
# Preview
~/.claude/contacts-bridge delete "Alex Schmidt"

# Actually delete
~/.claude/contacts-bridge delete "Alex Schmidt" --force
```

### birthdays-today

Show contacts with a birthday today.

```bash
~/.claude/contacts-bridge birthdays-today
```

### birthdays-upcoming

Show upcoming birthdays within the next N days.

```bash
~/.claude/contacts-bridge birthdays-upcoming <days>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `days` | Yes | Number of days to look ahead |

```bash
~/.claude/contacts-bridge birthdays-upcoming 30
```

Output example:

```
3 birthday(s) in the next 30 days:
  Tomorrow (5.3): Anna Müller
  In 12 days (17.3): Max Weber
  In 28 days (2.4): Lisa Schmidt
```

## Common Workflows

### Quick contact lookup

```bash
~/.claude/contacts-bridge search "Rob"
~/.claude/contacts-bridge show "Robert Johnson"
```

### Birthday check

```bash
~/.claude/contacts-bridge birthdays-today
~/.claude/contacts-bridge birthdays-upcoming 7
```
