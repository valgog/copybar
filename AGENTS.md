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
  Preview.swift               one-line preview, invisible-character stripping, blank check
  HotKeySpec.swift            "cmd+alt+v" → virtual key code + modifiers
Sources/CopyBar/              The AppKit app
  main.swift                  --unregister-login-item flag, single instance, app start
  AppDelegate.swift           status item, menu building, picking, hotkey handling
  ClipboardWatcher.swift      polls NSPasteboard, filters, captures text/images
  HistoryStore.swift          in-memory history + on-disk persistence, thumbnails
  PreviewPanel.swift          hover preview panel next to the menu
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
  `.html` and Chrome's `org.chromium.web-custom-data` (a web page's own
  formats, e.g. Google Docs/Slides) when present, so ⌘V keeps formatting.
  A copy with no visible plain text and no image (a Google Slides slide
  is HTML plus web custom data) becomes a `.rich` item: every UTI-named
  type is saved as is (each ≤ 32 MB, 64 MB in total; `dyn.` and old-style
  alias names are skipped). Its `text` is a Google Slides slide's text
  or `Preview.htmlText` of its HTML; its `label` and `symbolName` come
  from `GoogleClip` (Google editor copies: Chrome's web custom data,
  parsed by `WebCustomData`, plus `org.chromium.source-url`) or the
  source app's name. A slide copy's HTML is empty; the slide is the
  `application/x-vnd.google-docs-drawings-page+wrapped` entry, whose
  `data` JSON holds `unresolvedCommands`, where `[15, id, _, i, text]`
  inserts text. ⇧-clicking a menu entry
  writes plain text only. Images: stored as PNG; picking one writes PNG
  and TIFF. File URLs (Finder copies) are skipped on purpose.
  Representations over 32 MB are not saved (a copy whose plain text or
  image is that big is skipped), and images over 100 megapixels are
  skipped; their size is read with `CGImageSourceCopyPropertiesAtIndex`
  before anything is decoded. Copies with
  nspasteboard.org concealed/transient markers are skipped when
  `ignore_concealed` is on, and so are apps in `ignored_apps`, matched
  case-insensitively by `org.nspasteboard.source` or the frontmost app's
  bundle id. On `NSWorkspace.didActivateApplicationNotification` the
  watcher polls at once. While a switch is in flight the copy may come
  from either app, so it is skipped if the app before *or* after the
  switch is ignored (copy-then-⌘Tab and ⌘Tab-then-copy both hold).
- **Dedup** is by SHA-256 of the plain text (text) or PNG data (images). A
  repeated copy replaces the old entry and moves to the top.
- **Persistence.** `~/Library/Application Support/CopyBar/index.json`
  holds a format `version` and the `items`, an array of `ClipItem`
  (Codable). If the index can't be decoded or its version isn't
  `HistoryStore.formatVersion`, the whole history is deleted on start, so
  bump that number whenever a change makes saved history unreadable.
  Each item's data is in `items/<uuid>/<n>.bin`, where `n` indexes
  `types`. Data is read from disk
  only when an item is picked. `ClipItem.text` holds only the first 1000 visible
  characters (menu title and tooltip); ⇧-picking reads the full text from
  the saved `public.utf8-plain-text` data (`HistoryStore.fullText(of:)`).
  Orphan folders are deleted on load.
  The history can hold secrets: folders are created 0700 and files 0600,
  and the `CopyBar` folder is chmodded to 0700 on every start.
- **Never activate the app before showing the menu.** `NSApp.activate`
  completes asynchronously and closes a menu that just opened. The hotkey
  menu is shown with `menu.popUp(...)` without activation. That also
  keeps focus in the user's app so they can press ⌘V themselves.
- **Hover previews.** `menu(_:willHighlight:)` starts a timer
  (`preview_delay`) in the `.common` run loop modes, which include the
  event tracking mode a menu runs in; `menuDidClose` hides the panel.
  `PreviewPanel` is a borderless non-activating `NSPanel` above the
  pop-up menu level that ignores the mouse and is shown with
  `orderFrontRegardless()`, so the menu stays open and keeps the
  keyboard. NSMenu has no API for an item's frame, so the panel goes
  beside the menu window (found in `NSApp.windows` at the pop-up menu
  level), level with the pointer or the menu's top. Copied HTML goes
  through `Preview.offlineHTML` before `NSAttributedString` renders it, so
  a preview never downloads images or stylesheets; HTML over 512 KB is
  shown as plain text. Plain text entries keep their tooltip instead;
  previewed entries drop it so the two don't overlap.
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
    it, because older builds would just launch. The flag also unregisters
    an item the user switched off (`.requiresApproval`, still listed) and
    exits with 1 if the item survives. Then the Makefile retries it as a
    normal app launch (`open -W -n`), checks again, and otherwise tells the
    user to remove the entry in System Settings > General > Login Items.
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
It is created on first run from `Settings.defaultFileContents` (folder
0700 and file 0600 when CopyBar creates them) and
reloaded when its modification date changes, checked every 2 s.
A symlinked config (dotfiles repos) is read through the link, but only if
the target is a regular file of at most 64 KB; otherwise CopyBar warns and
uses the defaults. An existing symlink, even a dangling one, is never
replaced or written through when creating the default file.
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
