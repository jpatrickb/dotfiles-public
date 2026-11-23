#!/bin/bash
# Tests for the starship prompt as chezmoi renders it (dot_config/starship.toml.tmpl + .chezmoitemplates/starship-*.toml):
# it must parse, render in every prompt situation, and use ONLY colours from its generated palette (the tiers derived
# from Omarchy's theme). The tiers across all 23 Omarchy themes are tested by .test/starship-tiers.sh.
# Renders happen with the real starship in throwaway directories and a sandboxed environment.
#   .test/starship.sh
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
command -v starship >/dev/null 2>&1 || { echo "starship not installed: skipped"; exit 0; }
command -v chezmoi >/dev/null 2>&1 || { echo "chezmoi not installed: skipped"; exit 0; }
T="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-starship-test.XXXXXX")"
[ -n "$T" ] && [ -d "$T" ] || { echo "could not create temp dir"; exit 2; }
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/          /'; }
mkdir -p "$T/home/.config"
printf '[data]\n  family = "arch"\n  env = "omarchy"\n' > "$T/cfg.toml"
chezmoi --source "$SRC" --config "$T/cfg.toml" --persistent-state "$T/st.db" --cache "$T/cache" --destination "$T/home" apply --include=files --force "$T/home/.config/starship.toml" >"$T/apply.log" 2>&1
CFG="$T/home/.config/starship.toml"
[ -s "$CFG" ] || { echo "could not render starship.toml:"; cat "$T/apply.log"; exit 2; }
sp() { # sp <dir> [starship prompt args...] : render in a sandboxed env, config under test
  local d=$1; shift
  env -i HOME="$T/home" PATH=/usr/bin:/bin TERM=xterm-256color LANG=C.UTF-8 STARSHIP_CONFIG="$CFG" "${EXTRA_ENV[@]}" \
    starship prompt --path "$d" --terminal-width 120 "$@"; }
EXTRA_ENV=(X=1)
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
# the truecolor values the prompt may use: every colour of the generated palette (as r;g;b). Prints how many 38;2 / 48;2
# sequences in the input use a colour NOT in it (bold/reset codes are ignored; a 256-colour or ANSI-slot code counts as stray).
PAL_RGB=$(python3 -I - "$CFG" <<'PY'
import tomllib,sys
p=tomllib.load(open(sys.argv[1],'rb'))['palettes']['omarchy']
print(' '.join(';'.join(str(int(v[i:i+2],16)) for i in (1,3,5)) for v in p.values()))
PY
)
stray_colours() { grep -aoE $'\x1b\\[[0-9;]*m' | tr -d '\033' | python3 -I -c '
import sys,re
pal=set(sys.argv[1].split()); n=0
for line in sys.stdin:
    body=line.strip()[1:-1].split(";")
    i=0
    while i<len(body):
        if body[i] in ("38","48"):
            if i+1<len(body) and body[i+1]=="2" and i+4<len(body):
                if ";".join(body[i+2:i+5]) not in pal: n+=1
                i+=5; continue
            n+=1; i+=2; continue
        if body[i] in ("30","31","32","33","34","35","36","37","90","91","92","93","94","95","96","97","40","41","42","43","44","45","46","47"): n+=1
        i+=1
print(n)' "$PAL_RGB"; }

echo "=== the file itself"
grep -qE '\{\{|\}\}' "$CFG" && bad "unrendered template syntax in starship.toml" "$(grep -nE '\{\{|\}\}' "$CFG" | head -3)" || ok "the template renders completely (no {{ }} left)"
grep -qE 'bg:pill_git_bg' "$CFG" && grep -qE 'bg:pill_lang_bg' "$CFG" && grep -qE 'bg:pill_dur_bg' "$CFG" && ok "the git / language / duration segments have their own tier backgrounds" || bad "tier backgrounds missing"
grep -qE 'rose-pine|dawn|THEME_MODE' "$CFG" && bad "old Rose Pine / light-dark leftovers" "$(grep -nE 'rose-pine|dawn|THEME_MODE' "$CFG")" || ok "no Rose Pine / Dawn / THEME_MODE leftovers"
out=$(env -i HOME="$T/home" PATH=/usr/bin:/bin STARSHIP_CONFIG="$CFG" starship print-config 2>&1 >/dev/null); [ -z "$out" ] && ok "starship parses the config with no warnings (unknown keys would be reported)" || bad "config warnings" "$out"
env -i HOME="$T/home" PATH=/usr/bin:/bin STARSHIP_CONFIG="$CFG" starship print-config 2>/dev/null | grep -q '^palette = "omarchy"' && ok "the active palette is the generated one for this machine (omarchy)" || bad "palette not omarchy"
python3 -I - "$CFG" <<'PY' && ok "the palette defines every role the format uses, all as #rrggbb" || bad "palette incomplete"
import tomllib,sys,re
d=tomllib.load(open(sys.argv[1],'rb')); p=d['palettes']['omarchy']
need="love foam iris pill_os_bg pill_os_fg pill_dir_bg pill_dir_fg pill_text pill_change pill_git_bg pill_lang_bg pill_dur_bg".split()
assert all(re.fullmatch(r'#[0-9a-f]{6}',p.get(k,'')) for k in need), [k for k in need if k not in p]
PY

echo; echo "=== renders (each must exit 0, print the prompt character and use only colours from the palette)"
# throwaway project dirs
mkdir -p "$T/plain" "$T/repo" "$T/node" "$T/rust" "$T/go" "$T/py"
( cd "$T/repo" && git init -q . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m i && echo a > f.txt && git add f.txt && git -c user.name=t -c user.email=t@t commit -q -m f && echo b >> f.txt && echo c > new.txt )
branch=$(git -C "$T/repo" branch --show-current)
echo '{}' > "$T/node/package.json"; printf '[package]\nname="x"\n' > "$T/rust/Cargo.toml"; printf 'module x\n' > "$T/go/go.mod"; echo 'print(1)' > "$T/py/a.py"
scenario() { # scenario <label> <dir> <expected visible text|-> [prompt args...]
  local label=$1 dir=$2 want=$3; shift 3
  local raw vis rc n
  raw=$(sp "$dir" "$@" 2>"$T/err"); rc=$?
  vis=$(printf '%s' "$raw" | strip)
  [ $rc -eq 0 ] && [ ! -s "$T/err" ] && ok "[$label] renders (exit 0, no stderr)" || { bad "[$label] render" "rc=$rc $(cat "$T/err")"; return; }
  case "$vis" in *❯*|*❮*) ok "[$label] the prompt character is there" ;; *) bad "[$label] no prompt character" "$vis" ;; esac
  n=$(printf '%s' "$raw" | stray_colours)
  [ "$n" = 0 ] && ok "[$label] every colour is one of the palette's" || bad "[$label] colours outside the palette: $n" "$(printf '%s' "$raw" | grep -aoE $'\x1b\\[[0-9;]*m' | cat -v | sort -u | head -4)"
  if [ "$want" != "-" ]; then case "$vis" in *"$want"*) ok "[$label] shows: $want" ;; *) bad "[$label] missing '$want'" "$vis" ;; esac; fi
}
scenario "git repo, dirty, 3s command" "$T/repo" "$branch"  --status 0 --cmd-duration 3000
scenario "git repo shows the directory" "$T/repo" "repo" --status 0
scenario "outside git"                 "$T/plain" "plain" --status 0
scenario "last command failed"         "$T/repo" "-" --status 1
scenario "vi command mode"             "$T/repo" "-" --status 0 --keymap vicmd
scenario "python project"              "$T/py"   "-" --status 0
scenario "node project"                "$T/node" "-" --status 0
scenario "rust project"                "$T/rust" "-" --status 0
scenario "go project"                  "$T/go"   "-" --status 0
EXTRA_ENV=(CONDA_DEFAULT_ENV=myenv); scenario "conda env" "$T/plain" "myenv" --status 0; EXTRA_ENV=(X=1)
vis=$(sp "$T/repo" --status 0 --cmd-duration 3000 | strip); case "$vis" in *3s*) ok "a 3-second command shows its duration" ;; *) bad "duration" "$vis" ;; esac
vis=$(sp "$T/repo" --status 0 --cmd-duration 100 | strip); case "$vis" in *"100ms"*|*" 0s"*) bad "a 100 ms command should show no duration (min_time is 2s)" "$vis" ;; *) ok "a fast command shows no duration" ;; esac
last=$(sp "$T/repo" --status 0 | strip | tail -1); first=$(sp "$T/repo" --status 0 | strip | head -1)
case "$last" in "❯"*) [ "$first" != "$last" ] && ok "two-line prompt: the prompt character sits on its own line" || bad "only one line" "$first" ;; *) bad "last line is not the prompt character" "$last" ;; esac
rgb() { python3 -I - "$CFG" "$1" <<'PY'
import tomllib,sys
v=tomllib.load(open(sys.argv[1],'rb'))['palettes']['omarchy'][sys.argv[2]]
print(';'.join(str(int(v[i:i+2],16)) for i in (1,3,5)))
PY
}
sp "$T/repo" --status 1 | grep -aqF $'\x1b[1;38;2;'"$(rgb love)m" && ok "a failed command turns the prompt character the palette's love colour (bold)" || bad "error colour"
sp "$T/repo" --status 0 | grep -aqF $'\x1b[1;38;2;'"$(rgb foam)m" && ok "a successful command shows it in the palette's foam colour (bold)" || bad "success colour"
# starship only honours --keymap for shells that support vi mode (zsh, fish, ...), so say zsh here
EXTRA_ENV=(STARSHIP_SHELL=zsh)
sp "$T/repo" --status 0 --keymap vicmd | grep -aqF '❮' && sp "$T/repo" --status 0 --keymap vicmd | grep -aqF $'\x1b[1;38;2;'"$(rgb iris)m" && ok "vi command mode (zsh): the ❮ symbol in the palette's iris colour (bold)" || bad "vicmd symbol/colour"
EXTRA_ENV=(X=1)

echo; echo "=== the OS icon (the OS module must produce a symbol on this machine)"
out=$(env -i HOME="$T/home" PATH=/usr/bin:/bin STARSHIP_CONFIG="$CFG" starship module os 2>&1 | strip | tr -d ' \n'); [ -n "$out" ] && ok "the OS pill has an icon here" || bad "empty OS icon"
python3 -I - "$CFG" <<'PY' && ok "the Linux fallback icon is the Arch logo, not the penguin (Omarchy is reported as plain Linux)" || bad "Linux fallback icon"
import tomllib,sys
s=tomllib.load(open(sys.argv[1],'rb'))['os']['symbols']
assert s['Linux']==s['Arch'], (s['Linux'],s['Arch'])
assert s['Linux']!='\U000f033d', 'still the penguin'
PY
if grep -q '^ID=omarchy' /etc/os-release 2>/dev/null; then   # starship's own detection on a real Omarchy machine
  [ "$out" = "$(printf '\U000f08c7')" ] && ok "on this Omarchy machine starship really draws the Arch logo" || bad "Omarchy shows the wrong OS icon" "$(printf '%s' "$out" | od -An -c | head -2)"
fi

echo; echo "=== readability and the tiers: see .test/starship-tiers.sh (every Omarchy theme, all three palettes)"
echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL STARSHIP CHECKS PASSED" || echo "SOME STARSHIP CHECKS FAILED"
exit $fail
