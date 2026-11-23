#!/bin/bash
# Table test for .chezmoitemplates/machine-class: feeds fake os / os-release / kernel / omarchy inputs
# and checks the "<family> <env>" answer. Needs only chezmoi, no container. Usage:
#   .test/detect.sh            (run from anywhere; CHEZMOI=/path/to/chezmoi to override the binary)
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
CZ="${CHEZMOI:-chezmoi}"
fail=0
# os | id | idLike | kernel | omarchy | expected | description
cases=(
  'linux|omarchy|arch|7.2.15-1-omarchy|true|arch omarchy|Omarchy (ID=omarchy, ID_LIKE=arch)'
  'linux|arch||6.9.1-arch1-1|false|arch native|plain Arch (no ID_LIKE)'
  'linux|arch||5.15.167.4-microsoft-standard-WSL2|false|arch wsl|Arch on WSL2'
  'linux|ubuntu|debian|6.8.0-45-generic|false|debian native|Ubuntu'
  'linux|ubuntu|debian|5.15.153.1-microsoft-standard-WSL2|false|debian wsl|Ubuntu on WSL2'
  'linux|debian||6.1.0-18-amd64|false|debian native|Debian (no ID_LIKE)'
  'darwin|||24.1.0|false|mac native|macOS'
  'linux|fedora|rhel centos|6.10.0-200.fc40|false|other native|unsupported distro'
  'linux|manjaro|arch|6.6.54-1-MANJARO|false|arch native|Arch derivative via ID_LIKE'
  'linux|||6.1.0|false|other native|Linux with no os-release data'
  'darwin|||24.1.0|true|mac native|Omarchy dir ignored off Linux'
  'linux|arch||4.4.0-19041-Microsoft|false|arch wsl|WSL1 uppercase Microsoft kernel string'
)
for c in "${cases[@]}"; do
  IFS='|' read -r os id like kernel omarchy want desc <<<"$c"
  tmpl="{{ includeTemplate \"machine-class\" (dict \"os\" \"$os\" \"id\" \"$id\" \"idLike\" \"$like\" \"kernel\" \"$kernel\" \"omarchy\" $omarchy) | trim }}"
  got="$("$CZ" --source "$SRC" execute-template "$tmpl" 2>&1)"
  if [ "$got" = "$want" ]; then printf '  PASS  %-14s %s\n' "$want" "$desc"
  else printf '  FAIL  %s: expected "%s", got "%s"\n' "$desc" "$want" "$got"; fail=1; fi
done
# The real machine through the real config template path (not faked): must produce a valid pair.
real="$("$CZ" --source "$SRC" execute-template '{{ includeTemplate "machine-class" (dict "os" .chezmoi.os "id" (get .chezmoi.osRelease "id" | default "") "idLike" (get .chezmoi.osRelease "idLike" | default "") "kernel" (get .chezmoi.kernel "osrelease" | default "") "omarchy" (stat "/usr/share/omarchy" | not | not)) | trim }}' 2>&1)"
case "$real" in
  mac\ *|arch\ *|debian\ *|other\ *) printf '  PASS  this machine detected as: %s\n' "$real" ;;
  *) printf '  FAIL  this machine: unexpected output "%s"\n' "$real"; fail=1 ;;
esac
echo; [ $fail -eq 0 ] && echo "ALL DETECTION CHECKS PASSED" || echo "SOME DETECTION CHECKS FAILED"
exit $fail
