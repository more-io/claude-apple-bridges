#!/bin/bash
# test.sh
# Copyright © 2026 Tobias Stöger (tstoegi). Licensed under the MIT License.
# Integration tests for claude-apple-bridges.
# Run via: make test  or  bash test.sh

BRIDGE_DIR="${BRIDGE_DIR:-$HOME/.claude}"  # override to test a build without touching the live install
PASS=0
FAIL=0

green='\033[0;32m'
red='\033[0;31m'
reset='\033[0m'

check() {
    local description="$1"
    local expected_exit="$2"
    shift 2
    local cmd=("$@")

    output=$("${cmd[@]}" 2>&1)
    actual_exit=$?

    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo -e "  ${green}✓${reset} $description"
        PASS=$((PASS + 1))
    else
        echo -e "  ${red}✗${reset} $description"
        echo "    → exit $actual_exit (expected $expected_exit)"
        echo "    → output: $output"
        FAIL=$((FAIL + 1))
    fi
}

check_contains() {
    local description="$1"
    local needle="$2"
    shift 2
    local cmd=("$@")

    output=$("${cmd[@]}" 2>&1)
    actual_exit=$?

    if [ "$actual_exit" -eq 0 ] && echo "$output" | grep -qi "$needle"; then
        echo -e "  ${green}✓${reset} $description"
        PASS=$((PASS + 1))
    else
        echo -e "  ${red}✗${reset} $description"
        echo "    → exit $actual_exit, looking for: '$needle'"
        echo "    → output: $output"
        FAIL=$((FAIL + 1))
    fi
}

# ─── reminders-bridge ────────────────────────────────────────────

echo ""
echo "reminders-bridge"
echo "────────────────"

RB="$BRIDGE_DIR/reminders-bridge"

check        "lists: exits 0"                  0  "$RB" lists
check_contains "lists: returns at least one list" "." "$RB" lists
check        "today: exits 0"                  0  "$RB" today
check        "overdue: exits 0"                0  "$RB" overdue
check_contains "search nonexistent: exits 0, no results" "No reminders" "$RB" search "xyzzy_nonexistent_42"
check        "incomplete missing arg: exits 1" 1  "$RB" incomplete
check        "items missing arg: exits 1"      1  "$RB" items
check        "add missing arg: exits 1"        1  "$RB" add
check        "set-due missing arg: exits 1"    1  "$RB" set-due
check        "complete missing arg: exits 1"   1  "$RB" complete
check        "delete missing arg: exits 1"     1  "$RB" delete
check        "unknown command: exits 1"        1  "$RB" xyzzy
check        "set-repeat missing arg: exits 1" 1  "$RB" set-repeat

# Write round trip for repeat rules, in a throwaway list of our own. It syncs
# via iCloud for the few seconds the test runs, and is removed at the end —
# also if the script is interrupted (trap).
RB_LIST="bridge-selftest-$$"
rb_cleanup() { "$RB" delete-list "$RB_LIST" >/dev/null 2>&1; }
trap rb_cleanup EXIT INT TERM
if "$RB" create-list "$RB_LIST" >/dev/null 2>&1; then
    "$RB" add "$RB_LIST" "no-due" >/dev/null 2>&1
    "$RB" add "$RB_LIST" "has-due" >/dev/null 2>&1
    "$RB" set-due "$RB_LIST" "has-due" "2030-01-07 09:00" >/dev/null 2>&1

    check          "set-repeat without due date: exits 1"  1  "$RB" set-repeat "$RB_LIST" "no-due" weekly
    check          "set-repeat unknown title: exits 1"     1  "$RB" set-repeat "$RB_LIST" "xyzzy_nonexistent_42" weekly
    check          "set-repeat invalid frequency: exits 1" 1  "$RB" set-repeat "$RB_LIST" "has-due" hourly
    check          "set-repeat weekly: exits 0"            0  "$RB" set-repeat "$RB_LIST" "has-due" weekly
    check_contains "set-repeat weekly: reads back"   "repeats: weekly"      "$RB" incomplete "$RB_LIST"
    check          "set-repeat monthly 2: exits 0"         0  "$RB" set-repeat "$RB_LIST" "has-due" monthly 2
    check_contains "set-repeat interval: reads back" "monthly (every 2)"    "$RB" incomplete "$RB_LIST"
    check          "set-repeat none: exits 0"              0  "$RB" set-repeat "$RB_LIST" "has-due" none
    if "$RB" incomplete "$RB_LIST" 2>&1 | grep -q "repeats:"; then
        echo -e "  ${red}✗${reset} set-repeat none: rule removed"; FAIL=$((FAIL + 1))
    else
        echo -e "  ${green}✓${reset} set-repeat none: rule removed"; PASS=$((PASS + 1))
    fi
    # A miss must never look like success — every mutating command exits 1
    # when the title does not exist (they used to print to stderr and exit 0).
    check          "set-due unknown title: exits 1"        1  "$RB" set-due   "$RB_LIST" "xyzzy_nonexistent_42" "2030-01-01 09:00"
    check          "set-notes unknown title: exits 1"      1  "$RB" set-notes "$RB_LIST" "xyzzy_nonexistent_42" "n"
    check          "rename unknown title: exits 1"         1  "$RB" rename    "$RB_LIST" "xyzzy_nonexistent_42" "x"
    check          "complete unknown title: exits 1"       1  "$RB" complete  "$RB_LIST" "xyzzy_nonexistent_42"
    check          "delete unknown title: exits 1"         1  "$RB" delete    "$RB_LIST" "xyzzy_nonexistent_42" --force
    check          "delete dry-run on a hit: exits 0"      0  "$RB" delete    "$RB_LIST" "has-due"
    check          "add --repeat without --due: exits 1"   1  "$RB" add "$RB_LIST" "half" --repeat weekly
    check_contains "add --due --repeat in one call"  "repeats weekly"       "$RB" add "$RB_LIST" "one-call" --due "2030-01-06 09:00" --repeat weekly
    check_contains "add --due --repeat: reads back"  "repeats: weekly"      "$RB" incomplete "$RB_LIST"
    rb_cleanup
else
    echo "  (skipped repeat round trip: could not create a test list)"
fi
trap - EXIT INT TERM

# ─── calendar-bridge ─────────────────────────────────────────────

echo ""
echo "calendar-bridge"
echo "───────────────"

CB="$BRIDGE_DIR/calendar-bridge"
TODAY=$(date +%Y-%m-%d)

check        "calendars: exits 0"              0  "$CB" calendars
check_contains "calendars: returns results"    "." "$CB" calendars
check        "today: exits 0"                  0  "$CB" today
check        "tomorrow: exits 0"               0  "$CB" tomorrow
check        "week: exits 0"                   0  "$CB" week
check        "events today: exits 0"           0  "$CB" events "$TODAY"
check        "free-slots today: exits 0"       0  "$CB" free-slots "$TODAY"
check_contains "free-slots: shows time range"  "–" "$CB" free-slots "$TODAY"
check_contains "search nonexistent: no results" "No events" "$CB" search "xyzzy_nonexistent_42"
check        "events missing arg: exits 1"     1  "$CB" events
check        "add missing arg: exits 1"        1  "$CB" add
check        "delete missing arg: exits 1"     1  "$CB" delete
check        "unknown command: exits 1"        1  "$CB" xyzzy

# ─── contacts-bridge ─────────────────────────────────────────────

echo ""
echo "contacts-bridge"
echo "───────────────"

KB="$BRIDGE_DIR/contacts-bridge"

check_contains "search nonexistent: no results" "No contacts" "$KB" search "xyzzy_nonexistent_42"
check        "birthdays-today: exits 0"        0  "$KB" birthdays-today
check        "birthdays-upcoming 30: exits 0"  0  "$KB" birthdays-upcoming 30
check        "search missing arg: exits 1"     1  "$KB" search
check        "show missing arg: exits 1"       1  "$KB" show
check        "add missing arg: exits 1"        1  "$KB" add
check        "update missing arg: exits 1"     1  "$KB" update
check        "delete missing arg: exits 1"     1  "$KB" delete
check        "birthdays-upcoming missing arg: exits 1" 1 "$KB" birthdays-upcoming
check        "unknown command: exits 1"        1  "$KB" xyzzy

# ─── notes-bridge ────────────────────────────────────────────────

echo ""
echo "notes-bridge"
echo "────────────"

NB="$BRIDGE_DIR/notes-bridge"

check        "accounts: exits 0"                    0  "$NB" accounts
check_contains "accounts: returns iCloud"           "iCloud" "$NB" accounts
check        "folders: exits 0"                     0  "$NB" folders
check_contains "folders: returns at least one"      "." "$NB" folders
check        "list: exits 0"                        0  "$NB" list
check_contains "search nonexistent: no results"     "No notes" "$NB" search "xyzzy_nonexistent_42"
check        "search missing arg: exits 1"          1  "$NB" search
check        "read missing arg: exits 1"            1  "$NB" read
check        "add missing arg: exits 1"             1  "$NB" add
check        "append missing arg: exits 1"          1  "$NB" append
check        "delete missing arg: exits 1"          1  "$NB" delete
check_contains "delete dry-run: no --force"        "Dry-run" "$NB" delete "xyzzy_nonexistent_42"
check        "unknown command: exits 1"             1  "$NB" xyzzy

# ─── mail-bridge ──────────────────────────────────────────────────

echo ""
echo "mail-bridge"
echo "───────────"

MB="$BRIDGE_DIR/mail-bridge"

check        "accounts: exits 0"                   0  "$MB" accounts
check_contains "accounts: returns at least one"    "." "$MB" accounts
check        "mailboxes: exits 0"                  0  "$MB" mailboxes
check_contains "mailboxes: returns INBOX"          "INBOX" "$MB" mailboxes
check        "list: exits 0"                       0  "$MB" list
check        "unread: exits 0"                     0  "$MB" unread
check_contains "search nonexistent: no results"   "No messages" "$MB" search "xyzzy_nonexistent_42"
check        "search missing arg: exits 1"         1  "$MB" search
check        "read missing arg: exits 1"           1  "$MB" read
check        "send missing arg: exits 1"           1  "$MB" send
check_contains "send dry-run: no --force"         "Dry-run" "$MB" send "test@test.com" "Subject" "Body"
check        "delete missing arg: exits 1"         1  "$MB" delete
check_contains "delete dry-run: no --force"       "Dry-run" "$MB" delete "1"
check        "unknown command: exits 1"            1  "$MB" xyzzy

# ─── tmux-bridge ──────────────────────────────────────────────────

echo ""
echo "tmux-bridge"
echo "───────────"

TB="$BRIDGE_DIR/tmux-bridge"

check        "sessions: exits 0"                  0  "$TB" sessions
check        "windows: exits 0"                   0  "$TB" windows
check        "panes: exits 0"                     0  "$TB" panes
check        "read missing arg: exits 1"          1  "$TB" read
check        "unknown command: exits 1"           1  "$TB" xyzzy

# Regression 18.09.2026: shell() waited for tmux before reading its pipe, so any
# capture larger than the pipe buffer (16–64 KB) deadlocked forever. Build a
# pane with well over 64 KB of scrollback and require read/snapshot to return.
# perl's alarm is the timeout (macOS has no `timeout`); a hang exits 142.
TB_TEST_SESSION="bridge-selftest-$$"
if tmux new-session -d -s "$TB_TEST_SESSION" -x 220 -y 50 2>/dev/null; then
    tmux send-keys -t "$TB_TEST_SESSION" \
        "clear; for i in \$(seq 1 1500); do printf 'Zeile %04d %0180d\\n' \$i 0; done" Enter
    sleep 3
    check    "read >64 KB pane: no pipe deadlock"  0  perl -e 'alarm shift; exec @ARGV' 10 "$TB" read "$TB_TEST_SESSION"
    check    "snapshot >64 KB: no pipe deadlock"   0  perl -e 'alarm shift; exec @ARGV' 10 "$TB" snapshot "$TB_TEST_SESSION"
    tmux kill-session -t "$TB_TEST_SESSION" 2>/dev/null
else
    echo "  (skipped large-pane test: could not start a tmux session)"
fi

# ─── apple-bridges-mcp ───────────────────────────────────────────

echo ""
echo "apple-bridges-mcp"
echo "─────────────────"

MCP="$BRIDGE_DIR/apple-bridges-mcp"
MCP_INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test.sh","version":"0"}}}'

# Sends the initialize handshake, then one request, the way an MCP client would
mcp() {
    printf '%s\n' "$MCP_INIT" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$1" | "$MCP"
}

check_contains "initialize: echoes supported protocol" '"protocolVersion":"2025-11-25"' mcp '{"jsonrpc":"2.0","id":2,"method":"ping"}'
check_contains "tools/list: lists reminders_read"  '"name":"reminders_read"' mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
check_contains "tools/list: lists reminders_write" '"name":"reminders_write"' mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
check_contains "tools/list: marks read tools"      '"readOnlyHint":true' mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
# notes-bridge checks a command's arguments before any AppleScript, so this needs no permission
check_contains "tools/call: runs the bridge"       'notes-bridge read' mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"notes_read","arguments":{"args":["read"]}}}'
check_contains "tools/call unknown tool: -32602"   '"code":-32602' mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"xyzzy","arguments":{"args":[]}}}'
check_contains "tools/call args not array: -32602" '"code":-32602' mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"reminders_read","arguments":{"args":"lists"}}}'
check_contains "unknown method: -32601"            '"code":-32601' mcp '{"jsonrpc":"2.0","id":2,"method":"xyzzy"}'

# The server refuses a command from the other side before the bridge runs. The list
# name does not exist, so even a broken check could not delete anything.
check_contains "read tool refuses a write command" 'belongs to reminders_write' mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"reminders_read","arguments":{"args":["delete-list","bridge-selftest-nonexistent"]}}}'
check_contains "write tool refuses a read command" 'belongs to reminders_read'  mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"reminders_write","arguments":{"args":["lists"]}}}'
check_contains "tool refuses an unknown command"   'Unknown command'            mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"reminders_read","arguments":{"args":["xyzzy"]}}}'
check_contains "tool refuses empty args"           'No command given'           mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"reminders_read","arguments":{"args":[]}}}'

# #7 follow-up — tmux is split like every other bridge. `write` types into any pane, so it
# stays alone on the write side and reading a pane no longer needs that approval.
check_contains "tools/list: lists tmux_read"       '"name":"tmux_read"'   mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
check_contains "tmux_read refuses write"           'belongs to tmux_write' mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"tmux_read","arguments":{"args":["write"]}}}'
check_contains "tmux_write refuses snapshot"       'belongs to tmux_read'  mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"tmux_write","arguments":{"args":["snapshot"]}}}'

# #7 follow-up — a flag that writes, on a command that reads: the side check looks at args[0]
# only, so `--mark-read` would walk past it. Refused before the bridge runs, so no mail is
# touched by this test.
check_contains "read tool refuses a writing flag"  'changes data'          mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"mail_read","arguments":{"args":["read","1","INBOX","--mark-read"]}}}'
check_contains "the flag is named in the refusal"  'mark-read'             mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"mail_read","arguments":{"args":["read","1","--mark-read"]}}}'

# Every command in a bridge's usage must be on a side; one on neither side is unreachable over MCP
MCP_TOOLS=$(mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
MCP_MISSING=""
for bin in "$BRIDGE_DIR"/*-bridge; do
    name=$(basename "$bin")
    for cmd in $("$bin" 2>&1 | awk -v b="$name" '$1 == b { print $2 }' | sort -u); do
        echo "$MCP_TOOLS" | grep -qE "$name $cmd( |\\\\n|\")" || MCP_MISSING="$MCP_MISSING $name:$cmd"
    done
done
if [ -z "$MCP_MISSING" ]; then
    echo -e "  ${green}✓${reset} tools/list: every bridge command is on a side"; PASS=$((PASS + 1))
else
    echo -e "  ${red}✗${reset} tools/list: every bridge command is on a side"
    echo "    → missing:$MCP_MISSING"; FAIL=$((FAIL + 1))
fi

# A usage line belongs to one side only, wrapped lines included (messages `send` spans two)
MCP_SHARED=$(echo "$MCP_TOOLS" | perl -MJSON::PP -ne '
    my $r = eval { decode_json($_) } or next;
    my %desc = map { $_->{name} => $_->{description} } @{ $r->{result}{tools} || [] };
    for my $read (grep { /_read$/ } keys %desc) {
        (my $write = $read) =~ s/_read$/_write/;
        my %on_write = map { $_ => 1 } grep { /^\s/ } split /\n/, ($desc{$write} // "");
        print "$read: $_\n" for grep { $on_write{$_} } split /\n/, $desc{$read};
    }')
if [ -z "$MCP_SHARED" ]; then
    echo -e "  ${green}✓${reset} tools/list: no usage line on both sides"; PASS=$((PASS + 1))
else
    echo -e "  ${red}✗${reset} tools/list: no usage line on both sides"
    echo "$MCP_SHARED" | sed 's/^/    → /'; FAIL=$((FAIL + 1))
fi

# #7 follow-up — every flag on a read side must be a known read-only one. The command lists
# are tested above, but a flag is what gets past them: `--mark-read` did. A new flag on a read
# command fails here until it is either listed as read-only or refused in `deniedReadFlags`.
MCP_READ_FLAGS_OK="--all --max --since --unread --raw --mid"   # read-only flags of the read sides
MCP_READ_FLAGS_DENIED="--mark-read"                            # writing flags, refused by the server
MCP_FLAGS=$(echo "$MCP_TOOLS" | perl -MJSON::PP -ne '
    my $r = eval { decode_json($_) } or next;
    for my $t (grep { $_->{name} =~ /_read$/ } @{ $r->{result}{tools} || [] }) {
        while ($t->{description} =~ /(--[a-z][a-z-]*)/g) { print "$t->{name} $1\n" }
    }' | sort -u)
MCP_UNKNOWN_FLAGS=""
MCP_UNREFUSED=""
while read -r tool flag; do
    [ -z "$flag" ] && continue
    case " $MCP_READ_FLAGS_OK " in *" $flag "*) continue ;; esac
    case " $MCP_READ_FLAGS_DENIED " in
        *" $flag "*)
            # Listed as writing: the server must refuse it on this read tool.
            refusal=$(mcp "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$tool\",\"arguments\":{\"args\":[\"read\",\"1\",\"$flag\"]}}}")
            echo "$refusal" | grep -q "changes data" || MCP_UNREFUSED="$MCP_UNREFUSED $tool $flag"
            continue ;;
    esac
    MCP_UNKNOWN_FLAGS="$MCP_UNKNOWN_FLAGS $tool $flag"
done <<EOF
$MCP_FLAGS
EOF
if [ -z "$MCP_UNKNOWN_FLAGS" ] && [ -z "$MCP_UNREFUSED" ]; then
    echo -e "  ${green}✓${reset} tools/list: every flag on a read side is read-only or refused"; PASS=$((PASS + 1))
else
    echo -e "  ${red}✗${reset} tools/list: every flag on a read side is read-only or refused"
    [ -n "$MCP_UNKNOWN_FLAGS" ] && echo "    → unclassified:$MCP_UNKNOWN_FLAGS"
    [ -n "$MCP_UNREFUSED" ] && echo "    → listed as writing but NOT refused:$MCP_UNREFUSED"
    FAIL=$((FAIL + 1))
fi

# #7 follow-up — the 256 KB ceiling. Needs a bridge that talks too much, so this runs against a
# throwaway directory with a fake notes-bridge beside a copy of the server; the real bridges and
# the real install are untouched.
MCP_BIG_DIR=$(mktemp -d)
cp "$MCP" "$MCP_BIG_DIR/" 2>/dev/null
cat > "$MCP_BIG_DIR/notes-bridge" <<'FAKE'
#!/bin/bash
[ $# -eq 0 ] && { printf 'Usage:\n  notes-bridge read <title>\n'; exit 0; }
perl -e 'print "x" x 300000'
FAKE
chmod +x "$MCP_BIG_DIR/notes-bridge"
MCP_BIG=$(printf '%s\n' "$MCP_INIT" '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"notes_read","arguments":{"args":["read","x"]}}}' \
    | "$MCP_BIG_DIR/apple-bridges-mcp" | tail -1)
MCP_BIG_LEN=${#MCP_BIG}
if echo "$MCP_BIG" | grep -q "Output cut after 256 KB" && [ "$MCP_BIG_LEN" -lt 280000 ]; then
    echo -e "  ${green}✓${reset} tools/call: output over 256 KB is cut and says so"; PASS=$((PASS + 1))
else
    echo -e "  ${red}✗${reset} tools/call: output over 256 KB is cut and says so"
    echo "    → response was $MCP_BIG_LEN chars, cut notice: $(echo "$MCP_BIG" | grep -c 'Output cut')"
    FAIL=$((FAIL + 1))
fi
rm -rf "$MCP_BIG_DIR"

# ─── Summary ─────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────"
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo -e "${green}All $TOTAL tests passed.${reset}"
    exit 0
else
    echo -e "${red}$FAIL/$TOTAL tests failed.${reset}"
    exit 1
fi
