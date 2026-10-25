APP        := CopyBar
ARCHS      := arm64 x86_64
MIN_MACOS  := 13.0
BUILD_DIR  := .build
APP_BUNDLE := $(BUILD_DIR)/$(APP).app
PREFIX     ?= /Applications
BUNDLE_ID  := com.valgog.copybar
# `-` signs ad hoc. macOS ties the Accessibility permission to the signature,
# and an ad hoc signature changes with every build. Set this to the name of a
# certificate in your keychain to keep the permission across reinstalls.
SIGN_IDENTITY ?= -

# SwiftPM always looks up XCTest, which the Command Line Tools don't ship,
# and warns about it on every build. The warning is harmless, so hide it.
SHELL      := /bin/bash
HIDE_XCTEST_WARNING := sed -e '/could not determine XCTest paths/d' -e "/unable to lookup item 'PlatformPath'/d"

INSTALLED  := $(PREFIX)/$(APP).app/Contents/MacOS/$(APP)

# Lets the installed copy remove its own login item. Older builds don't know
# the flag (they would just start), so only call it if the binary has it.
define unregister_login_item
-@if [ -x "$(INSTALLED)" ] && grep -qa -- --unregister-login-item "$(INSTALLED)"; then \
		"$(INSTALLED)" --unregister-login-item; \
	fi
endef

.PHONY: all app install uninstall test run clean

all: app

# Builds each architecture separately and merges them with lipo. This works
# with just the Xcode Command Line Tools (`xcode-select --install`).
app:
	@set -eo pipefail; bins=""; \
	for arch in $(ARCHS); do \
		triple=$$arch-apple-macosx$(MIN_MACOS); \
		swift build -c release --triple $$triple 2>&1 | $(HIDE_XCTEST_WARNING); \
		bins="$$bins $$(swift build -c release --triple $$triple --show-bin-path 2>/dev/null)/$(APP)"; \
	done; \
	rm -rf "$(APP_BUNDLE)"; \
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"; \
	lipo -create $$bins -output "$(APP_BUNDLE)/Contents/MacOS/$(APP)"; \
	cp Support/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"; \
	codesign --force --options runtime --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)"; \
	echo "Built $(APP_BUNDLE) ($$(lipo -archs "$(APP_BUNDLE)/Contents/MacOS/$(APP)"))"

install: app
	-@pkill -x $(APP) 2>/dev/null || true
	@# Wait for it to quit, or the new copy would see it and exit.
	@for i in $$(seq 50); do pgrep -x $(APP) >/dev/null || break; sleep 0.1; done
	$(unregister_login_item)
	rm -rf "$(PREFIX)/$(APP).app"
	cp -R "$(APP_BUNDLE)" "$(PREFIX)/"
	@# A new ad hoc build no longer matches the old Accessibility grant,
	@# which then looks enabled but does nothing. Clear it so macOS asks again.
	@if [ "$(SIGN_IDENTITY)" = "-" ]; then tccutil reset Accessibility $(BUNDLE_ID) >/dev/null 2>&1 || true; fi
	open "$(PREFIX)/$(APP).app"
	@echo "Installed to $(PREFIX)/$(APP).app"

uninstall:
	-@pkill -x $(APP) 2>/dev/null || true
	$(unregister_login_item)
	rm -rf "$(PREFIX)/$(APP).app"
	@echo "Removed the app. Your history and settings are kept in"
	@echo "  ~/Library/Application Support/CopyBar and ~/.config/copybar"

test:
	swift test

run:
	swift run $(APP)

clean:
	rm -rf $(BUILD_DIR)
