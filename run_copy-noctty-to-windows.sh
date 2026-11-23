#!/bin/bash
# [custom] Copies the Noctty (Ghostty fork) config out to the Windows host. Noctty is the Windows terminal for now
# (Otty lacked functionality there, and is the Mac's terminal only). Noctty runs natively on Windows
# and reads %LOCALAPPDATA%\noctty\config.ghostty, which WSL's ~/.config can't
# reach, so we copy across /mnt/c. The generated colour palette (omarchy-theme.conf, included by config.ghostty) is
# copied next to it.
#
# One-way (source -> Windows). If the Windows copy was edited directly and
# differs, it's saved as config.ghostty.bak first so nothing is lost; to keep
# such edits, copy it back to ~/.config/noctty/config.ghostty and `chezmoi add` it.
#
# No-op everywhere except WSL. DOTFILES_WIN_MOUNT overrides /mnt/c so tests can fake the Windows drive.
set -euo pipefail

SRC="$HOME/.config/noctty/config.ghostty"

if [ ! -d "${DOTFILES_WIN_MOUNT:-/mnt/c}" ] || ! command -v cmd.exe >/dev/null 2>&1; then
  exit 0
fi
[ -f "$SRC" ] || exit 0

LOCALAPPDATA_WIN="$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r' || true)"
DEST_DIR="$(wslpath "$LOCALAPPDATA_WIN" 2>/dev/null || true)/noctty"
if [ -z "$LOCALAPPDATA_WIN" ] || [ ! -d "$(dirname "$DEST_DIR")" ]; then
  echo "noctty sync: couldn't resolve %LOCALAPPDATA%, skipping (if cmd.exe says 'Exec format error', WSL interop is off: see docs/arch-wsl.md)" >&2
  exit 0
fi

mkdir -p "$DEST_DIR"
DEST="$DEST_DIR/config.ghostty"
if [ -f "$DEST" ] && ! cmp -s "$SRC" "$DEST"; then
  cp "$DEST" "$DEST.bak"
  echo "noctty sync: Windows copy differed; previous version saved as config.ghostty.bak"
fi
cp "$SRC" "$DEST"
echo "config.ghostty synced to $DEST"
# The generated palette that config.ghostty includes (config-file = omarchy-theme.conf, relative to this directory).
PALETTE="$(dirname "$SRC")/omarchy-theme.conf"
[ -f "$PALETTE" ] && cp "$PALETTE" "$DEST_DIR/omarchy-theme.conf" && echo "omarchy-theme.conf synced to $DEST_DIR"
exit 0
