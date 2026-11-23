#!/bin/bash
# Tests for scripts/sync-omarchy-theme.py (Omarchy's current theme -> Otty and Noctty theme files) and for the
# Omarchy theme-set hook that runs it. Everything happens in throwaway directories with fake theme folders: the
# real Omarchy theme is only READ, never changed, and no real repo is written to.
#   .test/theme-sync.sh
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$SRC/scripts/sync-omarchy-theme.py"
HOOK="$SRC/dot_config/omarchy/hooks/theme-set.d/executable_20-dotfiles-theme-sync"
command -v python3 >/dev/null 2>&1 || { echo "python3 not installed: skipped"; exit 0; }
T="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-themesync-test.XXXXXX")"
[ -n "$T" ] && [ -d "$T" ] || { echo "could not create temp dir"; exit 2; }
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/          /'; }
py() { python3 -I "$GEN" "$@"; }

mkrepo() { mkdir -p "$1"; : > "$1/.chezmoi.toml.tmpl"; }
mktheme() { # mktheme <dir> <bg> <fg> <p0..p15 as 16 words> : a fake Omarchy theme dir (ghostty.conf, colors.toml, ../theme.name)
  local d=$1 bg=$2 fg=$3; shift 3; mkdir -p "$d"
  { echo "background = $bg"; echo "foreground = $fg"; echo "cursor-color = $fg"; echo "selection-background = #222222"; echo "selection-foreground = $fg"; echo
    local i=0; for c in "$@"; do echo "palette = $i=$c"; i=$((i+1)); done
    echo "# omarchy-glass begin"; echo "background-opacity = 0.65"; echo "gtk-custom-css = /usr/share/omarchy/default/gtk/glass.css"; echo "# omarchy-glass end"; } > "$d/ghostty.conf"
  printf 'mode = "%s"\n' "${MODE:-dark}" > "$d/colors.toml"; echo "${NAME:-faketheme}" > "$(dirname "$d")/theme.name"; }
DARK=('#0a0a14' '#ff4d6d' '#7be0ad' '#ffd66b' '#82aaff' '#c792ea' '#89ddff' '#d0d0ff' '#3b3b50' '#ff6b88' '#9eebbf' '#ffe28a' '#a0c0ff' '#daa6f7' '#a8e6ff' '#ffffff')
LIGHT=('#faf4ed' '#b4637a' '#286983' '#ea9d34' '#56949f' '#907aa9' '#d7827e' '#575279' '#9893a5' '#b4637a' '#286983' '#ea9d34' '#56949f' '#907aa9' '#d7827e' '#575279')

echo "=== generator on a synthetic DARK theme"
mkrepo "$T/repo1"; mktheme "$T/cur1/theme" '#0a0a14' '#d0d0ff' "${DARK[@]}"
out=$(py --theme-dir "$T/cur1/theme" --repo "$T/repo1" 2>&1); rc=$?
[ $rc -eq 0 ] && ok "exit 0" || bad "exit $rc" "$out"
O="$T/repo1/dot_config/otty/themes/omarchy.ottytheme"; N="$T/repo1/dot_config/noctty/omarchy-theme.conf"
[ -f "$O" ] && [ -f "$N" ] && ok "both output files are written (and their directories created)" || bad "outputs missing"
python3 -I - "$O" "${DARK[@]}" <<'PY' && ok "the Otty theme is valid TOML with exactly the input's 16 palette colours, foreground and background" || bad "Otty theme content"
import tomllib,sys
d=tomllib.load(open(sys.argv[1],'rb')); want=sys.argv[2:]
t=d['terminal']; assert t['palette']==want, (t['palette'],want)
assert t['foreground']=='#d0d0ff' and t['background']=='#0a0a14' and t['cursor']=='#d0d0ff' and t['cursor-text']=='#0a0a14'
assert d['meta']['name']=='Omarchy'
assert d['selection']['background']=='#222222' and d['selection']['foreground']=='#d0d0ff'
PY
[ "$(grep -c '^palette = ' "$N")" = 16 ] && grep -q '^palette = 0=#0a0a14$' "$N" && grep -q '^palette = 15=#ffffff$' "$N" && grep -q '^background = #0a0a14$' "$N" && ok "the Noctty file has the 16 palette lines and the right background" || bad "Noctty file" "$(cat "$N")"
# (look at real settings only: the generated header comments mention these words on purpose)
grep -hvE '^\s*#' "$N" "$O" | grep -qiE '^\s*(background-opacity|gtk-custom-css)\b|omarchy-glass' && bad "Omarchy's window-glass settings leaked into an output" "$(grep -hvE '^\s*#' "$N" "$O" | grep -iE 'opacity|gtk|glass')" || ok "Omarchy-only window-glass settings (opacity, GTK stylesheet path) are not copied"
head -1 "$O" | grep -q 'faketheme (dark)' && ok "the header says which Omarchy theme and mode it came from" || bad "header" "$(head -1 "$O")"
grep -q 'GENERATED' "$N" && grep -q 'GENERATED' "$O" && ok "both files are marked GENERATED / do not edit" || bad "no GENERATED marker"

echo; echo "=== idempotent and quiet when nothing changed"
a=$(stat -c %Y "$O" "$N"); sleep 1.1; out=$(py --theme-dir "$T/cur1/theme" --repo "$T/repo1" 2>&1); b=$(stat -c %Y "$O" "$N")
[ "$a" = "$b" ] && echo "$out" | grep -c unchanged | grep -q 2 && ok "second run: both files reported unchanged and not rewritten (no mtime change, so the repo stays clean)" || bad "idempotency" "$out"
py --check --theme-dir "$T/cur1/theme" --repo "$T/repo1" 2>/dev/null && ok "--check: exit 0 when everything is up to date" || bad "--check should be 0"

echo; echo "=== a LIGHT theme replaces it"
MODE=light NAME=dawn mktheme "$T/cur2/theme" '#faf4ed' '#575279' "${LIGHT[@]}"
py --check --theme-dir "$T/cur2/theme" --repo "$T/repo1" 2>/dev/null; [ $? -eq 1 ] && ok "--check: exit 1 when the theme would change the files (and nothing was written)" || bad "--check should be 1"
grep -q '#0a0a14' "$O" && ok "--check wrote nothing" || bad "--check modified a file"
py --theme-dir "$T/cur2/theme" --repo "$T/repo1" 2>/dev/null
grep -q 'dawn (light)' "$O" && grep -q '#faf4ed' "$O" && ! grep -q '#0a0a14' "$O" && grep -q '^background = #faf4ed$' "$N" && ok "switching to the light theme rewrites both files completely" || bad "light theme" "$(head -3 "$O")"

echo; echo "=== bad input must never clobber good output"
cp "$O" "$T/good.otty"; cp "$N" "$T/good.noctty"
badtheme() { # badtheme <label> <sed expression applied to a valid ghostty.conf>
  mktheme "$T/bad/theme" '#0a0a14' '#d0d0ff' "${DARK[@]}"; sed -i "$2" "$T/bad/theme/ghostty.conf"
  out=$(py --theme-dir "$T/bad/theme" --repo "$T/repo1" 2>&1); rc=$?
  [ $rc -eq 2 ] && cmp -s "$O" "$T/good.otty" && cmp -s "$N" "$T/good.noctty" && ok "$1: exit 2, existing files untouched" || bad "$1" "rc=$rc $out"; }
badtheme "a missing palette entry"   '/^palette = 7=/d'
badtheme "a malformed colour"        's/^palette = 3=.*/palette = 3=#12345/'
badtheme "a named colour"            's/^palette = 4=.*/palette = 4=blue/'
badtheme "a palette index of 16"     's/^palette = 15=/palette = 16=/'
badtheme "no background"             '/^background = /d'
out=$(py --theme-dir "$T/nonexistent" --repo "$T/repo1" 2>&1); rc=$?; [ $rc -eq 2 ] && cmp -s "$O" "$T/good.otty" && ok "no theme directory at all: exit 2, existing files untouched" || bad "missing theme dir" "rc=$rc $out"
out=$(py --theme-dir "$T/cur2/theme" --repo "$T/notarepo" 2>&1); rc=$?; [ $rc -eq 2 ] && [ ! -e "$T/notarepo" ] && ok "a directory that is not the dotfiles repo: exit 2 and nothing created" || bad "wrong repo" "rc=$rc $out"

echo; echo "=== Neovim: Omarchy's generated neovim.lua is copied unchanged (third output)"
SPEC='return {
  { "omacom/aether.nvim", name = "aether", opts = { colors = { bg = "#0a0a14" } } },
  { "LazyVim/LazyVim", opts = { colorscheme = "aether" } },
}'
V="$T/nvim/dot_config/nvim/lua/plugins/theme.lua"
mkrepo "$T/nvim"; mktheme "$T/cur3/theme" '#0a0a14' '#d0d0ff' "${DARK[@]}"; printf '%s\n' "$SPEC" > "$T/cur3/theme/neovim.lua"
out=$(py --theme-dir "$T/cur3/theme" --repo "$T/nvim" 2>&1); rc=$?
[ $rc -eq 0 ] && [ -f "$V" ] && ok "neovim.lua is copied to lua/plugins/theme.lua in the repo" || bad "nvim copy" "rc=$rc $out"
diff <(tail -n +4 "$V") "$T/cur3/theme/neovim.lua" >/dev/null && ok "the body is Omarchy's file byte for byte; only a 3-line GENERATED header is added" || bad "body differs" "$(diff <(tail -n +4 "$V") "$T/cur3/theme/neovim.lua" | head -5)"
head -3 "$V" | grep -q '^-- GENERATED' && head -1 "$V" | grep -q 'faketheme (dark)' && ok "the header (Lua comments) names the theme and says do not edit" || bad "nvim header" "$(head -3 "$V")"
a=$(stat -c %Y "$V"); sleep 1.1; out=$(py --theme-dir "$T/cur3/theme" --repo "$T/nvim" 2>&1); [ "$a" = "$(stat -c %Y "$V")" ] && [ "$(echo "$out" | grep -c unchanged)" = 3 ] && ok "second run: all three outputs unchanged and not rewritten" || bad "nvim idempotency" "$out"
printf '%s\n' "${SPEC//aether/other}" > "$T/cur3/theme/neovim.lua"; py --theme-dir "$T/cur3/theme" --repo "$T/nvim" 2>/dev/null; grep -q 'other' "$V" && ok "a changed neovim.lua (new theme) is picked up" || bad "nvim change not picked up"
# the theme has no neovim.lua: the terminal files still sync, the existing nvim file is left alone, exit 0
cp "$V" "$T/good.nvim"; rm "$T/cur3/theme/neovim.lua"; rm -f "$T/nvim/dot_config/otty/themes/omarchy.ottytheme"
out=$(py --theme-dir "$T/cur3/theme" --repo "$T/nvim" 2>&1); rc=$?
[ $rc -eq 0 ] && cmp -s "$V" "$T/good.nvim" && [ -f "$T/nvim/dot_config/otty/themes/omarchy.ottytheme" ] && echo "$out" | grep -q 'skipped' && ok "no neovim.lua in the theme: exit 0, terminal files written, the existing theme.lua untouched, the skip is reported" || bad "missing neovim.lua" "rc=$rc $out"
# invalid neovim.lua: refused, and NOTHING is written (the terminal files too: validation happens before any write)
badnvim() { # badnvim <label> <content-producing command>
  rm -rf "$T/nvim2"; mkrepo "$T/nvim2"; mkdir -p "$T/nvim2/dot_config/nvim/lua/plugins"; cp "$T/good.nvim" "$T/nvim2/dot_config/nvim/lua/plugins/theme.lua"
  mktheme "$T/cur4/theme" '#0a0a14' '#d0d0ff' "${DARK[@]}"; eval "$2" > "$T/cur4/theme/neovim.lua"
  out=$(py --theme-dir "$T/cur4/theme" --repo "$T/nvim2" 2>&1); rc=$?
  [ $rc -eq 2 ] && cmp -s "$T/nvim2/dot_config/nvim/lua/plugins/theme.lua" "$T/good.nvim" && [ ! -e "$T/nvim2/dot_config/otty" ] && ok "$1: exit 2, nothing written anywhere" || bad "$1" "rc=$rc $out"; }
badnvim "no 'return {'"              'printf "%s\n" "local x = 1" "vim.cmd.colorscheme(\"x\")"'
badnvim "no colorscheme"             'printf "%s\n" "return { { \"a/b\" } }"'
badnvim "a binary file"              'printf "return {\0 colorscheme }"'
badnvim "an oversized file"          'python3 -I -c "print(\"return { -- colorscheme\\n\" + \"-- x\\n\" * 40000 + \"}\")"'

echo; echo "=== the Omarchy theme-set hook (fake HOME, stand-in chezmoi, fake repo)"
mkhome() { local h=$1; mkdir -p "$h/.local/state/omarchy/current" "$T/bin_$2"
  mktheme "$h/.local/state/omarchy/current/theme" '#0a0a14' '#d0d0ff' "${DARK[@]}"
  printf '#!/bin/sh\n[ "$1" = source-path ] && echo "%s"\n' "$3" > "$T/bin_$2/chezmoi"; chmod +x "$T/bin_$2/chezmoi"; }
mkrepo "$T/repo3"; mkdir -p "$T/repo3/scripts"; cp "$GEN" "$T/repo3/scripts/"
mkhome "$T/h3" 3 "$T/repo3"
# the stand-in chezmoi also records every `apply` it is asked for
printf '#!/bin/sh\n[ "$1" = source-path ] && echo "%s"\n[ "$1" = apply ] && echo "$*" >> "%s/applied"\nexit 0\n' "$T/repo3" "$T" > "$T/bin_3/chezmoi"
env -i HOME="$T/h3" PATH="$T/bin_3:/usr/bin:/bin" bash "$HOOK" faketheme; rc=$?
[ $rc -eq 0 ] && [ -f "$T/repo3/dot_config/otty/themes/omarchy.ottytheme" ] && ok "the hook runs the generator against the chezmoi source and writes the files" || bad "hook run" "rc=$rc"
grep -q 'exit status: 0' "$T/h3/.local/state/dotfiles-theme-sync.log" && grep -q "theme 'faketheme'" "$T/h3/.local/state/dotfiles-theme-sync.log" && ok "it logs the theme name and the result to ~/.local/state/dotfiles-theme-sync.log" || bad "log" "$(cat "$T/h3/.local/state/dotfiles-theme-sync.log" 2>&1)"
[ "$(cat "$T/applied" 2>/dev/null)" = "apply --include=files $T/h3/.config/starship.toml" ] && ok "after a good run the hook applies ONLY ~/.config/starship.toml (so the prompt follows the theme live)" || bad "hook apply" "$(cat "$T/applied" 2>&1)"
# a broken theme: the hook must still exit 0 (a failing hook would show up as 'Hook failed' on every theme switch) and say why
sed -i '/^palette = 7=/d' "$T/h3/.local/state/omarchy/current/theme/ghostty.conf"
env -i HOME="$T/h3" PATH="$T/bin_3:/usr/bin:/bin" bash "$HOOK" broken; rc=$?
[ $rc -eq 0 ] && grep -q 'exit status: 2' "$T/h3/.local/state/dotfiles-theme-sync.log" && [ "$(wc -l < "$T/applied")" = 1 ] && ok "a broken theme: the hook still exits 0, the log records the failure, and nothing is applied" || bad "hook with broken theme" "rc=$rc $(cat "$T/h3/.local/state/dotfiles-theme-sync.log")"
mkhome "$T/h4" 4 "$T/nowhere"
env -i HOME="$T/h4" PATH="$T/bin_4:/usr/bin:/bin" bash "$HOOK" x; rc=$?
[ $rc -eq 0 ] && grep -q 'generator not found' "$T/h4/.local/state/dotfiles-theme-sync.log" && ok "no dotfiles repo on this machine: exit 0, logged, nothing done" || bad "hook without repo" "rc=$rc"
printf '#!/bin/sh\nexit 1\n' > "$T/bin_4/chezmoi"; mkdir -p "$T/h4/.local/share/chezmoi"
env -i HOME="$T/h4" PATH="$T/bin_4:/usr/bin:/bin" bash "$HOOK" x; [ $? -eq 0 ] && ok "chezmoi itself failing: still exit 0 (falls back to ~/.local/share/chezmoi)" || bad "hook with failing chezmoi"

echo; echo "=== against Omarchy's REAL current theme (read-only input, output to a temp repo)"
REAL="$HOME/.local/state/omarchy/current/theme"
if [ -r "$REAL/ghostty.conf" ]; then
  mkrepo "$T/repo5"; out=$(py --theme-dir "$REAL" --repo "$T/repo5" 2>&1); rc=$?
  [ $rc -eq 0 ] && ok "the real current theme converts cleanly" || bad "real theme" "$out"
  python3 -I - "$T/repo5/dot_config/otty/themes/omarchy.ottytheme" "$REAL/ghostty.conf" <<'PY' && ok "and its 16 colours match Omarchy's own ghostty.conf exactly" || bad "real palette mismatch"
import tomllib,sys,re
d=tomllib.load(open(sys.argv[1],'rb'))['terminal']['palette']
pal={}
for l in open(sys.argv[2]):
    m=re.match(r'\s*palette\s*=\s*(\d+)=(#[0-9a-fA-F]{6})',l)
    if m: pal[int(m.group(1))]=m.group(2).lower()
assert d==[pal[i] for i in range(16)]
PY
else echo "  (no Omarchy theme on this machine: skipped)"; fi

echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL THEME-SYNC CHECKS PASSED" || echo "SOME THEME-SYNC CHECKS FAILED"
exit $fail
