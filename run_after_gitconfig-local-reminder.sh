#!/bin/sh
# [custom] After every apply, nag until ~/.gitconfig.local has real values.
if grep -qE "FILL ME IN|fill-me-in@example\.invalid" "$HOME/.gitconfig.local" 2>/dev/null; then
  echo "!! Edit ~/.gitconfig.local: set your git name and email (placeholders still in place)." >&2
fi
exit 0
