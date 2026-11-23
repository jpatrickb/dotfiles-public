#!/bin/bash
# [custom] Switch the login shell to zsh. No-ops if it already is (this Mac
# has been zsh-by-default since Catalina; a fresh Ubuntu machine defaults to
# bash). Safe/reversible -- just the /etc/passwd shell field, `chsh` back
# anytime.
set -euo pipefail

# The Arch family (Arch, Arch on WSL, Omarchy) uses bash, not zsh: see modify_dot_bashrc. Same rule as
# .chezmoitemplates/machine-class: ID=arch, or "arch" in ID_LIKE. (DOTFILES_OS_RELEASE lets tests fake the file.)
if [ -r "${DOTFILES_OS_RELEASE:-/etc/os-release}" ]; then
  . "${DOTFILES_OS_RELEASE:-/etc/os-release}"
  case " ${ID:-} ${ID_LIKE:-} " in
    *" arch "*) echo "==> Arch family: bash is the shell here, skipping this zsh-only script."; exit 0 ;;
  esac
fi

ZSH_PATH="$(command -v zsh || true)"
[ -n "$ZSH_PATH" ] || exit 0
# Canonicalize: on Arch /usr/sbin is a symlink to /usr/bin, and chsh only
# accepts the path listed in /etc/shells.
ZSH_PATH="$(readlink -f "$ZSH_PATH")"
if [ -r /etc/shells ] && ! grep -qx "$ZSH_PATH" /etc/shells; then
  echo "==> Adding $ZSH_PATH to /etc/shells..."
  echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null || true
fi

if [ "$(readlink -f "${SHELL:-}" 2>/dev/null || true)" != "$ZSH_PATH" ]; then
  echo "==> Switching login shell to zsh ($ZSH_PATH)..."
  chsh -s "$ZSH_PATH" || echo "  (chsh failed -- run it yourself: chsh -s $ZSH_PATH)"
fi
