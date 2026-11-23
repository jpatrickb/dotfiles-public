#!/bin/bash
# [custom] zsh-autosuggestions / fast-syntax-highlighting via git clone
# instead of assuming Homebrew paths (apt and pacman systems). No-ops on this Mac (Homebrew already
# provides both -- see the multi-path search in dot_zshrc).
set -euo pipefail
umask 022   # zsh compaudit rejects group-writable completion dirs (umask 002 hosts)

command -v apt-get >/dev/null 2>&1 || command -v pacman >/dev/null 2>&1 || exit 0

# The Arch family (Arch, Arch on WSL, Omarchy) uses bash, not zsh: see modify_dot_bashrc. Same rule as
# .chezmoitemplates/machine-class: ID=arch, or "arch" in ID_LIKE. (DOTFILES_OS_RELEASE lets tests fake the file.)
if [ -r "${DOTFILES_OS_RELEASE:-/etc/os-release}" ]; then
  . "${DOTFILES_OS_RELEASE:-/etc/os-release}"
  case " ${ID:-} ${ID_LIKE:-} " in
    *" arch "*) echo "==> Arch family: bash is the shell here, skipping this zsh-only script."; exit 0 ;;
  esac
fi

mkdir -p "$HOME/.zsh/plugins"
[ -d "$HOME/.zsh/plugins/zsh-autosuggestions" ] || \
  git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/plugins/zsh-autosuggestions"
[ -d "$HOME/.zsh/plugins/fast-syntax-highlighting" ] || \
  git clone --depth 1 https://github.com/z-shell/F-Sy-H.git "$HOME/.zsh/plugins/fast-syntax-highlighting"
