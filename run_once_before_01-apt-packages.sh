#!/bin/bash
# [custom] apt package baseline for a fresh Ubuntu/Debian WSL or VM. No-ops
# instantly anywhere apt isn't the package manager (this Mac).
set -euo pipefail

command -v apt-get >/dev/null 2>&1 || exit 0

echo "==> Installing apt packages..."
sudo apt-get update
sudo apt-get install -y \
  git curl unzip xz-utils jq zsh tmux ripgrep fd-find bat fontconfig build-essential \
  python3 python3-venv

# Optional extras, installed one by one: not every Ubuntu release packages
# them, and one missing package must not abort the rest (run_once_before_02 installs
# upstream fallbacks for delta and lazygit; btop, gum and inotify-tools have none: skipped if apt lacks them,
# and the shell functions that need them (gd needs gum, rsw needs inotify-tools) then just report the missing command).
for p in git-delta fastfetch gh btop lazygit gum inotify-tools; do
  apt-cache show "$p" >/dev/null 2>&1 && sudo apt-get install -y "$p" || true
done

# xclip: clipboard for the pbcopy/pbpaste aliases and Neovim's clipboard=unnamedplus.
# Needs an X display (WSLg on WSL, or a desktop session), so skip headless servers.
if grep -qi microsoft /proc/version 2>/dev/null || [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  sudo apt-get install -y xclip || true
fi

# fastfetch isn't in older Ubuntu releases (e.g. 24.04); use its PPA there.
if ! command -v fastfetch >/dev/null 2>&1 && . /etc/os-release && [ "${ID:-}" = ubuntu ]; then
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch \
    && sudo apt-get update && sudo apt-get install -y fastfetch || true
fi

# Node/npm are NOT installed here: apt's npm drags in ~500 node-* packages.
# run_once_before_02 installs the official Node tarball into ~/.local instead.

mkdir -p "$HOME/.local/bin"
# Debian/Ubuntu install bat/fd under different binary names -- symlink to the
# names this config (and Mason LSP tooling) expects.
command -v bat >/dev/null 2>&1 || ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
command -v fd  >/dev/null 2>&1 || ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
