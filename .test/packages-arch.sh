#!/bin/bash
# Checks that every package named in the Arch install scripts really exists in the configured repos
# (pacman -Si), so a typo cannot break a fresh install. Needs pacman with a synced database (any Arch box,
# including Omarchy); skips elsewhere. AUR names are checked with yay/paru when one is installed.
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
command -v pacman >/dev/null 2>&1 || { echo "pacman not available: skipped"; exit 0; }
fail=0; n=0
check() { # check <script> <pacman-script|omarchy-script>
  local f="$SRC/$1" names
  case "$2" in
    pacman)  # the multi-line `sudo pacman -Syu ... \` list, without options
      names=$(awk '/^sudo pacman -Syu/{go=1; next} go{print} go && !/\\$/{exit}' "$f" | tr -d '\\' | tr ' ' '\n' | grep -vE '^$|^-') ;;
    omarchy) # packages=( ... ) (official repos only)
      names=$(sed -n '/^packages=(/s/^packages=(\(.*\))/\1/p' "$f" | tr ' ' '\n' | grep -v '^$') ;;
  esac
  [ -n "$names" ] || { echo "  FAIL  could not read package names from $1"; fail=1; return; }
  for p in $names; do
    n=$((n+1))
    pacman -Si "$p" >/dev/null 2>&1 && printf '  PASS  %-22s (%s)\n' "$p" "$1" || { printf '  FAIL  %-22s not found in the repos (%s)\n' "$p" "$1"; fail=1; }
  done
}
check run_once_before_01-pacman-packages.sh pacman
check run_once_before_01b-omarchy-packages.sh omarchy
# AUR names: they must exist, and ble.sh must be the 0.4 package (blesh, the 0.3.4 one, cannot draw the prompt's colours)
helper=$(command -v yay || command -v paru || true)
for f in run_once_before_01b-omarchy-packages.sh run_once_before_01-pacman-packages.sh; do
  grep -qE '(^aur_packages=\(blesh-git\)|(yay|paru) -S .* blesh-git)' "$SRC/$f" && ! grep -qE '(^aur_packages=\(blesh\)|(yay|paru) -S [^|]* blesh( |\)|$|"))' "$SRC/$f" \
    && printf '  PASS  %-22s asks for blesh-git, not blesh (%s)\n' blesh-git "$f" || { printf '  FAIL  %s does not ask for blesh-git\n' "$f"; fail=1; }
done
if [ -n "$helper" ]; then
  n=$((n+1)); "$helper" -Si blesh-git >/dev/null 2>&1 && printf '  PASS  %-22s (AUR, via %s)\n' blesh-git "$(basename "$helper")" || { printf '  FAIL  blesh-git not found in the AUR\n'; fail=1; }
else echo "  (no yay/paru: AUR name check skipped)"; fi
echo; echo "checked $n names"; [ $fail -eq 0 ] && echo "ALL PACKAGE NAMES EXIST" || echo "SOME PACKAGE NAMES MISSING"
exit $fail
