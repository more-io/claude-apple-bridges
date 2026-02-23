#!/bin/bash
# test.sh
# Copyright © 2026 Tobias Stöger (tstoegi). Licensed under the MIT License.
# Integration tests for claude-apple-bridges.
# Run via: make test  or  bash test.sh

BRIDGE_DIR="${HOME}/.claude"
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
