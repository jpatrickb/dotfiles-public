#!/bin/bash
# [custom] Herdr (terminal workspace for coding agents), via its official
# installer. Linux and macOS; puts `herdr` in ~/.local/bin. Re-running
# updates it. Non-fatal: a network hiccup shouldn't fail the whole apply.
set -uo pipefail

if command -v herdr >/dev/null 2>&1 || [ -x "$HOME/.local/bin/herdr" ]; then exit 0; fi
command -v curl >/dev/null 2>&1 || exit 0

echo "==> Installing herdr..."
# ~/.local/bin goes on PATH for the installer only: it warns "not in your PATH" otherwise, which is just noise on a fresh
# machine (the shell config adds it to every new shell).
curl -fsSL https://herdr.dev/install.sh | PATH="$HOME/.local/bin:$PATH" sh \
  || echo "herdr install failed; retry with: curl -fsSL https://herdr.dev/install.sh | sh" >&2
exit 0
