#!/bin/bash
# Usage: unregister-login-item.sh /path/to/CopyBar.app
#
# Runs the installed copy with --unregister-login-item so it removes its own
# login item. macOS keys login items to the signature, so no other build can
# remove that entry. The flag exits with 1 if the item is still there; then it
# is retried as a normal app launch through `open`, in case ServiceManagement
# doesn't accept a copy started from the terminal, and checked once more.
#
# A build that predates the flag would just start the app, so a run that is
# still going after a few seconds is stopped and reported as too old.

app=$1
bin="$app/Contents/MacOS/$(basename "$app" .app)"
name=$(basename "$app" .app)
hint="remove it by hand in System Settings > General > Login Items."

[ -x "$bin" ] || exit 0

# Runs the flag; returns its exit status, or 2 if it didn't exit in time.
run_flag() {
	"$bin" --unregister-login-item 2>"${1:-/dev/stderr}" &
	local pid=$!
	for _ in $(seq 50); do
		kill -0 "$pid" 2>/dev/null || { wait "$pid"; return; }
		sleep 0.1
	done
	kill "$pid" 2>/dev/null
	wait "$pid" 2>/dev/null
	return 2
}

run_flag /dev/null
case $? in
	0) exit 0 ;;
	2) echo "The installed $name is too old to remove its own login item; $hint"; exit 0 ;;
esac
open -W -n -g "$app" --args --unregister-login-item
run_flag || echo "Could not remove the $name login item; $hint"
