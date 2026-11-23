#!/bin/bash
# [custom] Omarchy only: install the packages this repo relies on that Omarchy does not already ship, using
# Omarchy's own helper (`pacman -S --needed`, i.e. only what is missing, NO system upgrade -- upgrades stay in
# Omarchy's update flow, which takes snapshots). Replaces run_once_before_01-pacman-packages.sh here, which
# does `pacman -Syu` and therefore skips itself on Omarchy. No-ops everywhere else.
#
# If a package cannot be found because the local package database is stale, this prints a hint instead of
# retrying with a full upgrade. Add packages here as later phases need them (chezmoi re-runs a run_once_
# script whenever its content changes).
set -uo pipefail

[ -d /usr/share/omarchy ] || exit 0
export PATH="/usr/share/omarchy/bin:$PATH"

# Official repos. lazygit/btop: shared tools. git-delta: the diff pager. atuin, direnv, bash-preexec: the bash
# equivalents of what zsh gets from its plugins and init (bash-preexec is atuin's hook when ble.sh is absent).
packages=(lazygit btop git-delta atuin direnv bash-preexec)
# AUR (community-built PKGBUILDs, so read them if you care). ble.sh gives bash autosuggestions and syntax
# highlighting; it is optional: if it cannot be installed, bash simply runs without it. It must be blesh-git (0.4):
# Arch's `blesh` is 0.3.4, which cannot draw the prompt's 24-bit colours (and the .bashrc does not load it).
aur_packages=(blesh-git)

if ! command -v omarchy-pkg-add >/dev/null 2>&1; then
  echo "==> omarchy-pkg-add not found; install these yourself: ${packages[*]} (AUR: ${aur_packages[*]})" >&2
  exit 0
fi

echo "==> Omarchy: ensuring packages are present: ${packages[*]}"
if ! omarchy-pkg-add "${packages[@]}"; then
  echo "!! Could not install some of: ${packages[*]}" >&2
  echo "!! If the package database is stale, update Omarchy the usual way, then run: chezmoi apply" >&2
fi

if command -v omarchy-pkg-aur-add >/dev/null 2>&1; then
  # blesh and blesh-git conflict, and `yay --noconfirm` will not remove a conflicting package: take the old one out first
  if pacman -Q blesh >/dev/null 2>&1 && ! pacman -Q blesh-git >/dev/null 2>&1; then
    echo "==> Replacing blesh (0.3.x) with blesh-git (0.4): 0.3.x cannot draw the prompt's colours"
    sudo pacman -R --noconfirm blesh || echo "!! Could not remove blesh; run: sudo pacman -R blesh" >&2
  fi
  echo "==> Omarchy: ensuring AUR packages are present: ${aur_packages[*]}"
  omarchy-pkg-aur-add "${aur_packages[@]}" \
    || echo "!! Could not install AUR packages (${aur_packages[*]}); bash works without them." >&2
fi
exit 0
