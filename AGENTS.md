# AGENTS.md

Context for coding agents working on CopyBar. For what the app does from a
user's point of view, read `README.md` first.

## What this is

CopyBar is a macOS menu bar clipboard history: a native Swift app (macOS
13+, universal arm64 + x86_64 binary) with **no third-party dependencies**.
Keep it that way unless the user asks otherwise; everything needed is in
AppKit, Carbon, ApplicationServices, ServiceManagement, ImageIO and
CryptoKit.

## Layout

```
Package.swift                 SwiftPM package, swift-tools 5.9, macOS 13
Sources/CopyBarCore/          Pure Foundation, no AppKit; unit tested
  Settings.swift              key = value config parser + default file text
  Preview.swift               one-line text preview trimming
  HotKeySpec.swift            "cmd+alt+v" → virtual key code + modifiers
Sources/CopyBar/              The AppKit app
  main.swift                  --unregister-login-item flag, single instance, app start
  AppDelegate.swift           status item, menu building, picking, hotkey handling
  ClipboardWatcher.swift      polls NSPasteboard, filters, captures text/images
  HistoryStore.swift          in-memory history + on-disk persistence, thumbnails
  ConfigFile.swift            ~/.config/copybar/config, reload on mtime change
  HotKey.swift                Carbon RegisterEventHotKey wrapper
  TextCaret.swift             text cursor position via the Accessibility API
  LoginItem.swift             SMAppService.mainApp register/unregister
  Log.swift                   os.Logger, subsystem com.valgog.copybar
Tests/CopyBarCoreTests/       XCTest for CopyBarCore only
Support/Info.plist            bundle metadata (LSUIElement, bundle id, version)
Makefile                      build/sign/install the .app
.github/workflows/build.yml   CI: swift test + make app on a macOS runner
```

Put logic that doesn't need AppKit into `CopyBarCore` and test it there.
The app target is not unit tested.

## Building and testing

| Command        | What it does                                                        |
|----------------|---------------------------------------------------------------------|
| `make app`     | Builds each arch with `--triple`, merges with `lipo`, signs → `.build/CopyBar.app` |
| `make install` | `make app`, then replaces `/Applications/CopyBar.app` and starts it  |
| `make uninstall` | Removes the app; keeps history and settings                       |
| `make test`    | `swift test` (needs full Xcode for XCTest)                          |
| `make run`     | `swift run CopyBar` without a bundle (no login item, no bundle id)   |

- **It only builds on macOS.** AppKit isn't available on Linux, so in a
  Linux sandbox you can't compile or run anything. Then CI is your compiler:
  push and check the `Build` workflow, and tell the user the change is
  untested on a real Mac.
- `make app` works with just the Command Line Tools. Building per arch
  and running `lipo` is deliberate: `swift build --arch arm64 --arch x86_64`
  needs full Xcode.
- SwiftPM prints a harmless "could not determine XCTest paths" warning on
  Command Line Tools installs. The Makefile filters it with
  `HIDE_XCTEST_WARNING`; the recipe uses `bash` with `pipefail` so real
  failures still stop the build. Keep that when editing recipes.
- Recipes must work when the repo path contains spaces: quote paths, and
  keep lists of paths in bash arrays (like `bins` in `app`), not in
  space-separated strings.
- `make install`/`uninstall` stop with an error if `PREFIX` is empty, so
  they never touch `/CopyBar.app`.
- CI also checks that the binary contains both architectures.
- The workflow runs with read-only `contents` permission and pins each
  action to a full commit SHA with a `# vX.Y.Z` comment. Keep both when
  adding or updating actions.

## Behavior and macOS quirks to preserve

- **Clipboard polling.** macOS has no clipboard-changed notification, so
  `ClipboardWatcher` polls `NSPasteboard.changeCount` (`poll_interval`,
  default 0.5 s). After CopyBar writes to the pasteboard itself, call
  `watcher.skipCurrentContents()`, then `store.moveToTop(id)`.
- **What gets captured.** Text: the plain string plus `.rtf`, `.rtfd`,
  `.html` when present, so ⌘V keeps formatting. ⇧-clicking a menu entry
  writes plain text only. Images: stored as PNG; picking one writes PNG
  and TIFF. File URLs (Finder copies) are skipped on purpose. Copies with
  nspasteboard.org concealed/transient markers are skipped when
  `ignore_concealed` is on, and so are apps in `ignored_apps`, matched
  case-insensitively by `org.nspasteboard.source` or the frontmost app's
  bundle id. On `NSWorkspace.didActivateApplicationNotification` the
  watcher polls at once and attributes the copy to the app that was
  frontmost *before* the switch, so copy-then-⌘Tab in an ignored app is
  still skipped.
- **Dedup** is by SHA-256 of the plain text (text) or PNG data (images). A
  repeated copy replaces the old entry and moves to the top.
- **Persistence.** `~/Library/Application Support/CopyBar/index.json` is
  an array of `ClipItem` (Codable). Each item's data is in
  `items/<uuid>/<n>.bin`, where `n` indexes `types`. Data is read from disk
  only when an item is picked. **Any new `ClipItem` field must be optional**
  so existing history still decodes. Orphan folders are deleted on load.
- **Never activate the app before showing the menu.** `NSApp.activate`
  completes asynchronously and closes a menu that just opened. The hotkey
  menu is shown with `menu.popUp(...)` without activation. That also
  keeps focus in the user's app so they can press ⌘V themselves.
- **Hotkey menu placement.** If Accessibility access is granted and the
  focused element reports a text cursor, the menu opens just below it
  (`TextCaret.rect()`). AX coordinates have a top-left origin on the main
  screen and are flipped to Cocoa coordinates. A rect with a NaN,
  infinite or negative component is ignored, and so is one whose menu
  anchor point (just below its bottom-left corner) is on no screen.
  Otherwise the menu opens under the status item via
  `statusItem.button?.performClick(nil)`. The Accessibility prompt is
  shown at most once per launch.
- **The hotkey uses Carbon `RegisterEventHotKey`.** It needs no
  permission. Don't switch it to an `NSEvent` global monitor, which needs
  Accessibility and can't swallow the key.
- **Signatures and permissions.** The app is ad hoc signed by default
  (`SIGN_IDENTITY=-`). macOS ties both the Accessibility grant and the
  login item to the signature, and an ad hoc signature changes on every
  build. So:
  - `make install` runs `tccutil reset Accessibility com.valgog.copybar`
    for ad hoc builds; otherwise a stale grant looks enabled but does
    nothing.
  - Before replacing the app, `make install`/`uninstall` run the
    *installed* binary with `--unregister-login-item`, so it removes its
    own login item. Without this, every reinstall adds a duplicate "Open at
    Login" entry. The Makefile only calls the flag if the binary contains
    it, because older builds would just launch.
  - `SIGN_IDENTITY="Some Cert"` signs with a stable certificate, which
    keeps the permissions across rebuilds.
  - `make app` signs with the Hardened Runtime (`--options runtime`),
    also for ad hoc builds. The app needs no entitlements; if a feature
    ever needs one (e.g. Apple Events), add an entitlements file to the
    `codesign` call.
- **Single instance.** `main.swift` takes an exclusive, non-blocking
  `flock` on `~/Library/Application Support/CopyBar/CopyBar.lock` and
  exits if another process holds it. The file descriptor stays open for
  the life of the process; the kernel releases the lock when it exits,
  even after a crash. `--unregister-login-item` is handled before the
  lock, so it works while CopyBar is running. `make install` waits for the
  old process to quit before starting the new one, so the new copy gets
  the lock.
- `LoginItem` and the single-instance lock do nothing without a bundle
  id, which is the case for `swift run`.

## Settings

The config file is `~/.config/copybar/config`, in `key = value` format.
Lines starting with `#` or `;` are comments, and lists are comma-separated.
It is created on first run from `Settings.defaultFileContents` and
reloaded when its modification date changes, checked every 2 s.
`AppDelegate.applySettings()` applies changes live.

To add a setting, update all of these together:
1. The property and its default on `Settings`.
2. A `case` in `Settings.parse`, with range or format validation that
   warns and keeps the default on bad input.
3. A commented entry in `Settings.defaultFileContents`.
4. The settings block in `README.md`.
5. `applySettings()`, if it must apply without a restart.
6. Tests in `SettingsTests`. `testDefaultFileParsesToDefaults` must keep
   passing: the default file must produce no warnings and equal
   `Settings()`.

## Conventions

- Match the existing style: 4-space indent, short doc comments that say
  *why*, `log.error`/`log.warning` with `privacy: .public` for messages
  users should see in `log stream`.
- Swift 5 language mode. Concurrency warnings from AppKit's `@MainActor`
  annotations are tolerated. Don't turn on strict concurrency without
  checking the whole app.
- No dependencies, no Xcode project: SwiftPM plus the Makefile only.
- Keep `README.md` in step with user-visible behavior.
- Commit messages and PR descriptions must not contain links to AI chat
  sessions or project threads. Crediting the assistant with a
  `Co-Authored-By:` line is fine.
