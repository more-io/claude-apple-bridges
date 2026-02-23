# Claude Apple Bridges — Makefile
# Copyright © 2026 Tobias Stöger (tstoegi). Licensed under the MIT License.
#
# Usage:
#   make install           Install all bridges to ~/.claude/
#   make install-reminders Install only reminders-bridge
#   make install-calendar  Install only calendar-bridge
#   make install-contacts  Install only contacts-bridge
#   make install-notes     Install only notes-bridge
#   make test              Run smoke tests (triggers permission dialogs on first run)
#   make clean             Remove compiled binaries from ~/.claude/

INSTALL_DIR := $(HOME)/.claude
PLIST_DIR   := /tmp

.PHONY: install install-reminders install-calendar install-contacts install-notes test clean

install: install-reminders install-contacts install-calendar install-notes
	@echo ""
	@echo "✅ All bridges installed to $(INSTALL_DIR)"
	@echo ""
	@echo "Next: run each binary once to grant permissions:"
	@echo "  ~/.claude/reminders-bridge lists"
	@echo "  ~/.claude/calendar-bridge today"
	@echo "  ~/.claude/contacts-bridge search test"
	@echo "  ~/.claude/notes-bridge accounts"

install-reminders:
	@echo "→ Building reminders-bridge..."
	@printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>NSRemindersUsageDescription</key><string>Claude Code needs access to Reminders to manage tasks.</string></dict></plist>' > $(PLIST_DIR)/reminders-info.plist
	swiftc reminders-bridge.swift -o $(INSTALL_DIR)/reminders-bridge \
	  -framework EventKit \
	  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker $(PLIST_DIR)/reminders-info.plist
	codesign --force --sign - --identifier com.claude.reminders-bridge $(INSTALL_DIR)/reminders-bridge
	@echo "  ✓ reminders-bridge installed"

install-contacts:
	@echo "→ Building contacts-bridge..."
	@printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>NSContactsUsageDescription</key><string>Claude Code needs access to Contacts to look up and manage contacts.</string></dict></plist>' > $(PLIST_DIR)/contacts-info.plist
	swiftc contacts-bridge.swift -o $(INSTALL_DIR)/contacts-bridge \
	  -framework Contacts \
	  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker $(PLIST_DIR)/contacts-info.plist
	codesign --force --sign - --identifier com.claude.contacts-bridge $(INSTALL_DIR)/contacts-bridge
	@echo "  ✓ contacts-bridge installed"

install-calendar:
	@echo "→ Building calendar-bridge..."
	@printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>NSCalendarsFullAccessUsageDescription</key><string>Claude Code needs access to Calendar to schedule and view events.</string></dict></plist>' > $(PLIST_DIR)/calendar-info.plist
	swiftc calendar-bridge.swift -o $(INSTALL_DIR)/calendar-bridge \
	  -framework EventKit \
	  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker $(PLIST_DIR)/calendar-info.plist
	codesign --force --sign - --identifier com.claude.calendar-bridge $(INSTALL_DIR)/calendar-bridge
	@echo "  ✓ calendar-bridge installed"

install-notes:
	@echo "→ Building notes-bridge..."
	swiftc notes-bridge.swift -o $(INSTALL_DIR)/notes-bridge
	codesign --force --sign - --identifier com.claude.notes-bridge $(INSTALL_DIR)/notes-bridge
	@echo "  ✓ notes-bridge installed"

test:
	@echo "Running integration tests (may trigger permission dialogs on first run)..."
	@bash test.sh

clean:
	rm -f $(INSTALL_DIR)/reminders-bridge
	rm -f $(INSTALL_DIR)/calendar-bridge
	rm -f $(INSTALL_DIR)/contacts-bridge
	rm -f $(INSTALL_DIR)/notes-bridge
	@echo "Removed all bridges from $(INSTALL_DIR)"
