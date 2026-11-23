#!/bin/bash
# [custom] Rebuilds bat's cache once after the hand-built Rose Pine themes were retired (bat now uses its
# built-in "ansi" theme; see dot_config/bat/config and .chezmoiremove). Without a rebuild the stale themes
# would linger in the cache. `--build` (not `--clear`) so any other custom bat syntaxes/themes you keep in
# ~/.config/bat/ are preserved. Replaces run_bat-cache-build.sh, which rebuilt on every apply.
# Ubuntu/Debian call the binary batcat; best-effort, never fails the apply.
set -uo pipefail
b="$(command -v bat || command -v batcat || true)"
[ -n "$b" ] && "$b" cache --build >/dev/null 2>&1
exit 0
