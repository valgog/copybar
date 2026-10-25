# CopyBar

A small clipboard history for the macOS menu bar.

CopyBar runs in the background and remembers what you copy. Click the
clipboard icon in the menu bar, or press **⌥⌘V** anywhere, to see your
recent copies and pick one. When you are typing, ⌥⌘V opens the menu right
at the text cursor; otherwise it opens under the menu bar icon. The picked entry goes back on the clipboard, so
you paste it with ⌘V as usual.

- **Text** is shown as one trimmed line (30 characters by default). Markdown
  is treated as text.
- **Rich text** (from web pages, Pages, Word…) keeps its formatting. Pasting
  with ⌘V keeps the formatting; the app's own plain-text paste (⇧⌘V in Google
  Docs, Chrome and Slack, ⌥⇧⌘V in most Mac apps) still works. Hold **⇧** while
  picking an entry to copy it as plain text only.
- **Images** are shown as thumbnails (50×50 by default).
- Copying something that is already in the history moves it to the top.
- Passwords copied from password managers (anything marked *concealed*, see
  [nspasteboard.org](http://nspasteboard.org)) are never saved.
- History is saved in `~/Library/Application Support/CopyBar` and survives
  restarts. Files copied in Finder are ignored.
- While the menu is open, keys **1**–**9** pick the first nine entries.

Requires macOS 13 or later. Runs natively on Apple Silicon and Intel.

## Install

You need the Xcode Command Line Tools (`xcode-select --install`), or Xcode.

```sh
git clone https://github.com/valgog/copybar.git
cd copybar
make install
```

This builds a universal `CopyBar.app`, copies it to `/Applications` and
starts it. The first time you press ⌥⌘V, macOS asks you to allow CopyBar in
**System Settings → Privacy & Security → Accessibility**. That access is
only used to find the text cursor; without it ⌥⌘V opens the menu under the
menu bar icon.

Each `make install` signs the app afresh, which makes macOS forget the
Accessibility permission, so you are asked again after reinstalling. To
avoid that, create a code signing certificate once (Keychain Access →
Certificate Assistant → Create a Certificate…, type *Code Signing*, name it
e.g. `CopyBar Dev`) and install with
`make install SIGN_IDENTITY="CopyBar Dev"`. To install somewhere else: `make install PREFIX=~/Applications`.
`make uninstall` removes the app but keeps your history and settings.

## Settings

Choose **Settings…** in the menu, or edit `~/.config/copybar/config`.
Changes apply within a couple of seconds, no restart needed.

```properties
max_items = 50          # entries to keep (1-1000)
text_length = 30        # characters of text shown per entry (5-500)
image_size = 50         # thumbnail size in points (16-512)
hotkey = cmd+alt+v      # modifiers: cmd, alt, ctrl, shift; `none` to turn off
launch_at_login = true
ignore_concealed = true # skip copies that password managers mark as secret
ignored_apps =          # comma-separated bundle IDs never to record
poll_interval = 0.5     # seconds between clipboard checks (0.1-10)
```

Find an app's bundle ID with `osascript -e 'id of app "Bitwarden"'`.

Unknown keys and invalid values are ignored and logged; see them with
`log stream --predicate 'subsystem == "com.valgog.copybar"'`.

## How it works

macOS has no "clipboard changed" event, so CopyBar checks the clipboard's
change counter every half second, which costs next to nothing. The global
shortcut uses the Carbon hot key API. The text cursor position comes from
the Accessibility API; apps that don't report it (some Electron apps,
terminals) get the menu under the menu bar icon instead.

## Development

```sh
make test   # unit tests for config parsing, previews and shortcuts
make run    # run from the terminal without building the .app
make app    # build .build/CopyBar.app
```
