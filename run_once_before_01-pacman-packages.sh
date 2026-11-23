#!/bin/bash
# [custom] Package baseline for Arch Linux (incl. Arch on WSL). No-ops anywhere
# pacman isn't the package manager. Arch ships current versions of nearly
# everything, so run_once_before_02 (upstream installers) mostly skips itself.
set -euo pipefail

command -v pacman >/dev/null 2>&1 || exit 0

# Omarchy updates itself through its own flow (with snapshots), and this script's `pacman -Syu` is a full
# system upgrade. Never run that from chezmoi on Omarchy: run_once_before_01b-omarchy-packages.sh installs
# only the packages that are missing, with no upgrade.
if [ -d /usr/share/omarchy ]; then
  echo "==> Omarchy detected: skipping the pacman -Syu package script (see run_once_before_01b-omarchy-packages.sh)."
  exit 0
fi

# Fresh Arch images (WSL, containers) have no initialized keyring.
if [ ! -f /etc/pacman.d/gnupg/trustdb.gpg ]; then
  sudo pacman-key --init
  sudo pacman-key --populate archlinux
fi

echo "==> Installing pacman packages..."
# -Syu not -Sy: Arch doesn't support partial upgrades.
sudo pacman -Syu --noconfirm --needed \
  base-devel git curl unzip jq tmux ripgrep fd bat fontconfig chezmoi \
  python nodejs npm neovim go rust terraform \
  git-delta github-cli fastfetch eza starship zoxide direnv atuin fzf tldr \
  tree-sitter-cli mise uv lazygit btop gum inotify-tools bash-preexec

# xclip: clipboard for the pbcopy/pbpaste aliases and Neovim's clipboard=unnamedplus.
# Needs an X display (WSLg on WSL, or a desktop session), so skip headless servers.
if grep -qi microsoft /proc/version 2>/dev/null || [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  sudo pacman -S --noconfirm --needed xclip || true
fi

# AUR helper: yay (the same one Omarchy ships), so AUR packages install the same way on every Arch machine. A fresh
# Arch (WSL, container) has none, so build yay-bin once with makepkg (base-devel and git are installed above). makepkg
# refuses to run as root, and a failure here is not fatal: the AUR packages below are optional.
bootstrap_yay() {
  [ "$(id -u)" -ne 0 ] || { echo "  (running as root: makepkg refuses, so no AUR helper was built)"; return 1; }
  local d; d="$(mktemp -d)"
  ( cd "$d" && git clone --depth 1 https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si --noconfirm )
  local rc=$?; rm -rf "$d"; return $rc
}
if ! command -v yay >/dev/null 2>&1 && ! command -v paru >/dev/null 2>&1; then
  echo "==> No AUR helper found: building yay (from the AUR, with makepkg)..."
  bootstrap_yay || echo "  (yay build failed -- optional; the AUR packages below are skipped. Retry: git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si)"
fi

# ble.sh: autosuggestions + syntax highlighting for bash (the arch family runs bash, not zsh). It is AUR-only, so it
# needs the helper above. Optional: bash works without it.
# It must be blesh-git (0.4): Arch's `blesh` is 0.3.4, which cannot draw the starship prompt's 24-bit colours (the
# .bashrc does not load it). blesh conflicts with blesh-git and --noconfirm will not remove it, so remove it first.
if ! pacman -Q blesh-git >/dev/null 2>&1; then
  if command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1; then
    if pacman -Q blesh >/dev/null 2>&1; then
      echo "==> Replacing blesh (0.3.x) with blesh-git (0.4)"
      sudo pacman -R --noconfirm blesh || true
    fi
  fi
  if command -v yay >/dev/null 2>&1; then
    yay -S --noconfirm --needed blesh-git || echo "  (ble.sh install failed -- optional; retry: yay -S blesh-git)"
  elif command -v paru >/dev/null 2>&1; then
    paru -S --noconfirm --needed blesh-git || echo "  (ble.sh install failed -- optional; retry: paru -S blesh-git)"
  else
    echo "==> ble.sh (optional, AUR) not installed: no AUR helper available. Install yay, then: yay -S blesh-git"
  fi
fi

mkdir -p "$HOME/.local/bin"
