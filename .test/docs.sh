#!/bin/bash
# Checks the markdown docs: every relative link points at a file that exists, every #anchor matches a heading in the target,
# and the retired setup (TPM's `prefix + I`, WezTerm as a thing to install) is not recommended anywhere.
#   .test/docs.sh
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok()  { pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
files=("$SRC/README.md" "$SRC"/docs/*.md)
anchor_of() { python3 -I -c '
import re,sys
for l in open(sys.argv[1],encoding="utf-8"):
    m=re.match(r"^#{1,6}\s+(.*?)\s*$",l)
    if m:
        a=re.sub(r"[^\w\s-]","",m.group(1).lower().replace("`","")).strip().replace(" ","-")
        print(a)' "$1"; }
for f in "${files[@]}"; do
  while IFS= read -r link; do
    target="${link%%#*}"; frag=""; [[ "$link" == *"#"* ]] && frag="${link#*#}"
    case "$target" in http*|mailto:*) continue;; esac
    if [ -z "$target" ]; then path="$f"; else path="$(dirname "$f")/$target"; fi
    if [ ! -e "$path" ]; then bad "$(basename "$f"): link to a missing file: $link"; continue; fi
    if [ -n "$frag" ]; then anchor_of "$path" | grep -qx -- "$frag" && ok || bad "$(basename "$f"): no heading for #$frag in $(basename "$path")"; else ok; fi
  done < <(grep -oE '\]\(([^)]+)\)' "$f" | sed -E 's/^\]\((.*)\)$/\1/' | grep -vE '^(http|mailto:)')
done
for f in "${files[@]}"; do
  grep -n 'prefix + I' "$f" | grep -v 'no plugin\|there is no' >/dev/null && bad "$(basename "$f"): still tells you to install tmux plugins with prefix + I"
  grep -niE 'winget install wez|wezterm' "$f" | grep -viE 'retired|delete|leftover' >/dev/null && bad "$(basename "$f"): recommends WezTerm"
done
ok
echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL DOCS CHECKS PASSED" || echo "SOME DOCS CHECKS FAILED"
exit $fail
