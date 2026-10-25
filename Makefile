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

# An empty PREFIX would make install/uninstall work on /CopyBar.app.
ifneq ($(filter install uninstall,$(MAKECMDGOALS)),)
ifeq ($(strip $(PREFIX)),)
$(error PREFIX is empty; set it to the folder for $(APP).app, e.g. PREFIX=/Applications)
endif
endif

# Lets the installed copy remove its own login item. macOS keys login items
# to the signature, so no other build can remove that entry. The flag exits
# with 1 if the item is still there; then it is retried as a normal app
# launch through `open`, in case ServiceManagement doesn't accept a copy
# started from the terminal, and checked once more.
LOGIN_ITEMS_HINT := remove it by hand in System Settings > General > Login Items.
define unregister_login_item
@if [ -x "$(INSTALLED)" ]; then \
		"$(INSTALLED)" --unregister-login-item 2>/dev/null \
			|| { open -W -n -g "$(PREFIX)/$(APP).app" --args --unregister-login-item; \
				"$(INSTALLED)" --unregister-login-item; } \
			|| echo "Could not remove the $(APP) login item; $(LOGIN_ITEMS_HINT)"; \
	fi
endef

.PHONY: all app install uninstall test run clean

all: app

# Builds each architecture separately and merges them with lipo. This works
# with just the Xcode Command Line Tools (`xcode-select --install`).
app:
	@set -eo pipefail; bins=(); \
	for arch in $(ARCHS); do \
		triple="$$arch-apple-macosx$(MIN_MACOS)"; \
		swift build -c release --triple "$$triple" 2>&1 | $(HIDE_XCTEST_WARNING); \
		bins+=("$$(swift build -c release --triple "$$triple" --show-bin-path 2>/dev/null)/$(APP)"); \
	done; \
	rm -rf "$(APP_BUNDLE)"; \
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"; \
	lipo -create "$${bins[@]}" -output "$(APP_BUNDLE)/Contents/MacOS/$(APP)"; \
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
	@echo "Builds installed before the login item fix can leave a stale $(APP) entry."
	@echo "If one is still listed, $(LOGIN_ITEMS_HINT)"

test:
	swift test

run:
	swift run $(APP)

clean:
	rm -rf $(BUILD_DIR)
