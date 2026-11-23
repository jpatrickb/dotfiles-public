#!/bin/bash
# Tests for dot_config/foot/modify_foot.ini (the copy-on-select block in Omarchy's foot.ini). It is applied into
# THROWAWAY homes against several kinds of starting file and validated with foot's own checker (foot -C).
#   .test/foot.sh
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-foot-test.XXXXXX")"
[ -n "$T" ] && [ -d "$T" ] || { echo "could not create temp dir"; exit 2; }
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/          /'; }
REAL_SUM="$(cksum < ~/.config/foot/foot.ini 2>/dev/null)"   # to prove at the end that the real file was never touched
HAVE_FOOT=0; command -v foot >/dev/null 2>&1 && HAVE_FOOT=1
SHIPPED=/usr/share/omarchy/config/foot/foot.ini
[ -r "$SHIPPED" ] || { cat > "$T/shipped.ini" <<'EOF'
[main]
include=~/.local/state/omarchy/current/theme/foot.ini
term=xterm-256color
font=JetBrainsMono Nerd Font:size=9
pad=14x14

[scrollback]
lines=10000

[cursor]
style=block
EOF
SHIPPED="$T/shipped.ini"; }

cfg() { printf '[data]\n  family = "arch"\n  env = "omarchy"\n' > "$T/cfg.toml"; }
cfg
applyfoot() { # applyfoot <label> <seed file or "-" for none>
  local h="$T/home_$1"; mkdir -p "$h/.config/foot"; [ "$2" != "-" ] && cp "$2" "$h/.config/foot/foot.ini"
  chezmoi --source "$SRC" --config "$T/cfg.toml" --persistent-state "$T/st_$1.db" --cache "$T/cache" --destination "$h" \
    apply --include=files,dirs --force "$h/.config/foot/foot.ini" > "$T/ap_$1.log" 2>&1
  [ -z "$(grep -v 'config file template has changed' "$T/ap_$1.log")" ] || bad "[$1] apply" "$(cat "$T/ap_$1.log")"; }
# section of the LAST selection-target line, and its value
last_sel() { python3 -I - "$1" <<'PY'
import sys,re
sec=None; last=None
for l in open(sys.argv[1],encoding='utf-8'):
    s=l.strip()
    m=re.match(r'^\[([^\]]+)\]$',s)
    if m: sec=m.group(1); continue
    m=re.match(r'^selection-target\s*=\s*(\S+)',s)
    if m: last=(sec,m.group(1))
print(f"{last[0]}|{last[1]}" if last else "none")
PY
}
check() { # check <label> <seed or -> <description>
  local l=$1 f="$T/home_$1/.config/foot/foot.ini"
  [ "$(grep -c '>>> dotfiles (chezmoi)' "$f")" = 1 ] && ok "[$l] exactly one managed block" || bad "[$l] block count" "$(cat "$f")"
  [ "$(last_sel "$f")" = "main|clipboard" ] && ok "[$l] the last selection-target in the file is 'clipboard' and it sits in [main]" || bad "[$l] selection-target" "$(last_sel "$f")  /  $(cat "$f")"
  if [ $HAVE_FOOT = 1 ]; then foot -C -c "$f" >/dev/null 2>"$T/footerr"; [ $? -eq 0 ] && [ ! -s "$T/footerr" ] && ok "[$l] foot --check-config accepts the result" || bad "[$l] foot rejects the file" "$(cat "$T/footerr")"; fi
  # idempotent
  cp "$f" "$T/before_$l"; applyfoot "$l" "-"
  cmp -s "$T/before_$l" "$f" && ok "[$l] re-apply changes nothing" || bad "[$l] not idempotent" "$(diff "$T/before_$l" "$f")"
  # text added by the user (or by Omarchy's font tool) outside the block survives
  sed -i 's/^pad=.*/pad=20x20/' "$f" 2>/dev/null; { echo; echo "# my own note"; } >> "$f"
  applyfoot "$l" "-"
  grep -q '^# my own note$' "$f" && [ "$(grep -c '>>> dotfiles (chezmoi)' "$f")" = 1 ] && ok "[$l] text added outside the block survives a re-apply (still one block)" || bad "[$l] user text lost or block duplicated"
}

echo "=== A. Omarchy's own foot.ini"
applyfoot a "$SHIPPED"
grep -q '^include=~/.local/state/omarchy/current/theme/foot.ini$' "$T/home_a/.config/foot/foot.ini" && ok "[a] Omarchy's theme include is still there, untouched" || bad "[a] theme include"
sed '/^# >>> dotfiles/,/^# <<< dotfiles/d' "$T/home_a/.config/foot/foot.ini" | cat -s > "$T/stripped_a"
diff <(cat -s "$SHIPPED") "$T/stripped_a" >/dev/null && ok "[a] with the block removed the file equals Omarchy's original exactly" || bad "[a] original content altered" "$(diff <(cat -s "$SHIPPED") "$T/stripped_a" | head -6)"
check a - "shipped"

echo; echo "=== B. a file the user (or Omarchy's font tool) already edited: font size changed, an extra line"
sed -e 's/size=9/size=8/' -e '/^\[cursor\]/a # user line in cursor' "$SHIPPED" > "$T/edited.ini"
applyfoot b "$T/edited.ini"
grep -q 'size=8' "$T/home_b/.config/foot/foot.ini" && grep -q '^# user line in cursor$' "$T/home_b/.config/foot/foot.ini" && ok "[b] the changed font size and the user's own line are preserved" || bad "[b] edits lost"
check b -

echo; echo "=== C. a conflicting selection-target already in [main]: ours is last, so it wins"
sed '/^\[main\]/a selection-target=primary' "$SHIPPED" > "$T/conflict.ini"
applyfoot c "$T/conflict.ini"; check c -

echo; echo "=== D. [main] is the LAST section (no header after it)"
printf '[cursor]\nstyle=block\n\n[main]\nfont=Mono:size=10\n' > "$T/mainlast.ini"
applyfoot d "$T/mainlast.ini"; check d -

echo; echo "=== E. an empty or missing file, and one without a [main] section"
applyfoot e -; check e -
printf '[cursor]\nstyle=beam\n' > "$T/nomain.ini"; applyfoot f "$T/nomain.ini"
grep -q '^style=beam$' "$T/home_f/.config/foot/foot.ini" && ok "[f] the existing content is kept" || bad "[f] content lost"
check f -

echo; echo "=== where it is installed"
for spec in "om arch omarchy yes" "pa arch native no" "ub debian native no"; do set -- $spec
  printf '[data]\n  family = "%s"\n  env = "%s"\n' $2 $3 > "$T/cfg_p_$1.toml"; mkdir -p "$T/hp_$1/.config"
  m=$(chezmoi --source "$SRC" --config "$T/cfg_p_$1.toml" --persistent-state "$T/stp_$1.db" --cache "$T/cache" --destination "$T/hp_$1" managed)
  if grep -qx '.config/foot/foot.ini' <<<"$m"; then [ "$4" = yes ] && ok "[$1] foot.ini is managed (Omarchy)" || bad "[$1] foot.ini managed where foot is not used"
  else [ "$4" = no ] && ok "[$1] foot.ini is not touched (foot is only Omarchy's terminal)" || bad "[$1] foot.ini missing on Omarchy"; fi
done
[ "$(cksum < ~/.config/foot/foot.ini 2>/dev/null)" = "$REAL_SUM" ] && ok "the real ~/.config/foot/foot.ini is byte-for-byte what it was before this test (every apply used a throwaway home)" || bad "the real foot.ini changed during the test"

echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL FOOT CHECKS PASSED" || echo "SOME FOOT CHECKS FAILED"
exit $fail
