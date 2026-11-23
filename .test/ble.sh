#!/bin/bash
# Interactive-terminal test of the bash setup WITH ble.sh attached. The other bash tests have no terminal, where ble.sh
# (correctly) does not load, so they cannot see problems that only exist in a real session: this one drives a real
# interactive bash through a pseudo-terminal (`script`) with the repo's config applied to a throwaway home.
# Found by it (the hard way, on a real machine): with ble.sh 0.3.x the starship prompt vanished, direnv stopped, four
# "unsupported readline function" warnings were printed, and the prompt's hex colours came out as other colours (0.3.x takes
# 38;2;r;g;b apart and reads r, g and b as separate colour codes). So the .bashrc loads ble.sh only from version 0.4 on, and
# this test asserts the EXACT palette colours reach the terminal.
#   .test/ble.sh
# Skipped unless this machine is Omarchy with ble.sh 0.4+, starship, direnv and `script` installed. Takes about a minute.
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
for need in /usr/share/blesh/ble.sh /usr/share/omarchy /etc/skel/.bashrc; do [ -e "$need" ] || { echo "skipped: $need not present"; exit 0; }; done
for cmd in starship direnv script chezmoi; do command -v $cmd >/dev/null 2>&1 || { echo "skipped: $cmd not installed"; exit 0; }; done
ver=$(grep -m1 -E '^[[:space:]]*_ble_init_version=[0-9]' /usr/share/blesh/ble.sh | sed 's/.*=//')
case $ver in 0.[0-3]*) echo "skipped: ble.sh $ver is older than 0.4 (the .bashrc deliberately does not load it; blesh-git is needed)"; exit 0 ;; esac
T="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ble-test.XXXXXX")"
[ -n "$T" ] && [ -d "$T" ] || { echo "could not create temp dir"; exit 2; }
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/          /'; }
strip() { sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b\][^\a]*\a//g; s/\x1b[()][0-9A-Z]//g; s/\r//g' | grep -v '^\s*$'; }

H="$T/home"; mkdir -p "$H/.config" "$H/proj" "$T/xdg/data" "$T/xdg/state" "$T/xdg/cache"
cp /etc/skel/.bashrc "$H/.bashrc"                       # Omarchy's own .bashrc, as on a real Omarchy machine
printf '[data]\n  family = "arch"\n  env = "omarchy"\n' > "$T/cfg.toml"
chezmoi --source "$SRC" --config "$T/cfg.toml" --persistent-state "$T/st.db" --cache "$T/cache" --destination "$H" apply --include=files,dirs --force "$H/.bashrc" "$H/.config/shell" "$H/.config/starship.toml" > "$T/apply.log" 2>&1
[ -z "$(grep -v 'config file template has changed' "$T/apply.log")" ] && ok "the real config is applied to a throwaway home" || bad "apply" "$(cat "$T/apply.log")"
printf 'export DIRENV_PROBE=loaded\n' > "$H/proj/.envrc"

# session <label> <keystrokes...>: an interactive bash in a pty; each argument is typed as a line, with pauses (the
# banner and ble.sh take a few seconds to come up). Output is stripped of escape codes into $T/out_<label>.
# COLORTERM=truecolor, as in a real terminal; the unstripped bytes are kept in $T/raw_<label> (for the colour checks)
session() {
  local l=$1; shift
  ( sleep 12; for c in "$@"; do printf '%s\n' "$c"; sleep 3; done; printf 'exit\n'; sleep 2 ) \
    | env -i HOME="${SH_HOME:-$H}" USER=tester PATH="${EXTRA_PATH:-}/usr/bin:/bin:/usr/local/bin" TERM=xterm-256color COLORTERM=truecolor LANG=C.UTF-8 \
        XDG_DATA_HOME="$T/xdg/data" XDG_STATE_HOME="$T/xdg/state" XDG_CACHE_HOME="$T/xdg/cache" \
        timeout 120 script -qec "bash -i" /dev/null 2>&1 | tee "$T/raw_$l" | strip > "$T/out_$l.txt"
}
# palette colour as the r;g;b of an SGR sequence
rgb() { python3 -I - "$H/.config/starship.toml" "$1" <<'PY'
import tomllib,sys
v=tomllib.load(open(sys.argv[1],'rb'))['palettes']['omarchy'][sys.argv[2]]
print(';'.join(str(int(v[i:i+2],16)) for i in (1,3,5)))
PY
}
count() { grep -c -- "$2" "$T/out_$1.txt"; }

echo; echo "=== a fresh interactive shell"
session fresh 'echo ATT=$((_ble_attached+10))' "direnv allow $H/proj 2>&1 | head -1" "cd $H/proj" 'echo RES=$DIRENV_PROBE-$((6*7))' 'cd /; echo CWD=$PWD' 'false' 'true'
[ "$(count fresh 'ATT=11')" -ge 1 ] && ok "ble.sh is attached (autosuggestions and highlighting are on)" || bad "ble.sh not attached" "$(head -8 "$T/out_fresh.txt")"
[ "$(count fresh 'unsupported readline')" = 0 ] && ok "no 'unsupported readline function' warnings at startup" || bad "readline warnings" "$(grep 'unsupported' "$T/out_fresh.txt" | head -4)"
[ "$(count fresh '❯')" -ge 3 ] && ok "the starship prompt is drawn (❯ appears on every prompt)" || bad "no starship prompt" "$(grep -E '\$ |\]\$' "$T/out_fresh.txt" | head -3)"
[ "$(count fresh 'RES=loaded-42')" -ge 1 ] && ok "direnv loads a project's .envrc when you cd into it" || bad "direnv did not load" "$(grep -E 'RES=|direnv' "$T/out_fresh.txt" | head -4)"
grep -qiE 'error|not found|insane|cannot find' "$T/out_fresh.txt" && bad "error text in the session" "$(grep -iE 'error|not found|insane|cannot find' "$T/out_fresh.txt" | head -4)" || ok "no error text anywhere in the session"
[ "$(count fresh 'CWD=/')" -ge 1 ] && ok "zoxide/cd still work (commands after the prompt hooks run normally)" || bad "shell stopped responding"

echo; echo "=== colours: the exact palette reaches the terminal (ble.sh 0.3.x garbled them; this is the regression test)"
R="$T/raw_fresh"; miss=""
for k in pill_os_bg pill_dir_bg pill_git_bg pill_lang_bg pill_dur_bg pill_text; do
  c=$(rgb $k); grep -aqE $'\x1b\\[[0-9;]*[34]8;2;'"$c"'[;m]' "$R" || miss="$miss $k($c)"
done
[ -z "$miss" ] && ok "every pill colour of the palette is sent as that exact 24-bit colour" || bad "palette colours missing from the terminal output:" "$miss"
grep -aqE $'\x1b\\[[0-9;]*38;2;'"$(rgb foam)"'[;m]' "$R" && ok "the prompt character after a successful command is the palette's foam colour" || bad "foam colour missing"
grep -aqE $'\x1b\\[[0-9;]*38;2;'"$(rgb love)"'[;m]' "$R" && ok "after a failed command (false) the prompt character is the palette's love colour (exit status reaches starship)" || bad "love colour missing after a failed command"

echo; echo "=== line editing: vi mode, grey letters (no block) for suggestions, Ctrl+G opens the editor"
mkdir -p "$T/fakebin"; printf '#!/bin/sh\nprintf "echo EDITED_OK\\n" > "$1"\n' > "$T/fakebin/nvim"; chmod +x "$T/fakebin/nvim"
EXTRA_PATH="$T/fakebin:" session vi 'echo SUGGEST_ME_PLEASE' 'echo vi-mode-is=$(set -o | grep -c "^vi.*on")'
[ "$(count vi 'vi-mode-is=1')" -ge 1 ] && ok "vi mode is on (set -o vi)" || bad "vi mode off" "$(grep -a 'vi-mode' "$T/out_vi.txt" | head -3)"
# the suggestion is drawn with a foreground colour only: the escape that starts it has no background (48;...) part
# (a second shell types the start of a line from the first one's history and leaves it unsent)
( sleep 12; printf 'echo SUGG'; sleep 4; printf '\x03'; sleep 1; printf 'exit\n'; sleep 2 ) \
  | env -i HOME="$H" USER=tester PATH="/usr/bin:/bin:/usr/local/bin" TERM=xterm-256color COLORTERM=truecolor LANG=C.UTF-8 \
      XDG_DATA_HOME="$T/xdg/data" XDG_STATE_HOME="$T/xdg/state" XDG_CACHE_HOME="$T/xdg/cache" timeout 90 script -qec "bash -i" /dev/null > "$T/raw_sug" 2>&1
sug=$(grep -ao $'\x1b\\[[0-9;]*m[^\x1b]*EST_ME_PLEASE' "$T/raw_sug" | tail -1)
case $sug in *'38;5;244m'*) ! printf '%s' "$sug" | grep -aq '48;' && ok "autosuggestions are coloured letters only (fg 244), no background block" || bad "suggestion has a background" "$(printf '%s' "$sug" | cat -v)";; *) bad "no suggestion colour found" "$(printf '%s' "$sug" | cat -v)";; esac
( sleep 12; printf 'echo typed-for-edit'; sleep 1; printf '\a'; sleep 4; printf '\n'; sleep 3; printf 'exit\n'; sleep 2 ) \
  | env -i HOME="$H" USER=tester PATH="$T/fakebin:/usr/bin:/bin:/usr/local/bin" TERM=xterm-256color COLORTERM=truecolor LANG=C.UTF-8 \
      XDG_DATA_HOME="$T/xdg/data" XDG_STATE_HOME="$T/xdg/state" XDG_CACHE_HOME="$T/xdg/cache" timeout 90 script -qec "bash -i" /dev/null 2>&1 | strip > "$T/out_edit.txt"
[ "$(count edit 'EDITED_OK')" -ge 2 ] && ok "Ctrl+G opens the command line in \$EDITOR, and the edited line runs" || bad "Ctrl+G did not run the editor" "$(tail -6 "$T/out_edit.txt")"
( sleep 12; printf 'false\n'; sleep 3; printf '\x1b'; sleep 3; printf 'i'; sleep 2; printf '\x03'; printf 'exit\n'; sleep 2 ) \
  | env -i HOME="$H" USER=tester PATH="/usr/bin:/bin:/usr/local/bin" TERM=xterm-256color COLORTERM=truecolor LANG=C.UTF-8 \
      XDG_DATA_HOME="$T/xdg/data" XDG_STATE_HOME="$T/xdg/state" XDG_CACHE_HOME="$T/xdg/cache" timeout 90 script -qec "bash -i" /dev/null > "$T/raw_mode" 2>&1
grep -aqE $'\x1b\\[[0-9;]*38;2;'"$(rgb iris)"'m❮' "$T/raw_mode" && ok "Esc (normal mode) turns the prompt character into ❮ in the palette's iris colour" || bad "no iris ❮ after Esc" "$(grep -ao '.\{30\}❮' "$T/raw_mode" | head -2 | cat -v)"
grep -aq 'INSERT' "$T/raw_mode" && bad "ble.sh's '-- INSERT --' line is still shown" || ok "no '-- INSERT --' line under the prompt"
last=$(grep -ao '❯\|❮' "$T/raw_mode" | tail -1); [ "$last" = "❯" ] && ok "back in insert mode (i) the character is ❯ again" || bad "character after i is $last"
grep -aqE $'\x1b\\[[0-9;]*38;2;'"$(rgb love)"'m❯' "$T/raw_mode" && ok "a failed command still makes the prompt character the love colour with vi mode on" || bad "love colour lost with the vi prompt"

echo; echo "=== only ble.sh 0.4 or newer is loaded (fake ble.sh files, the real .bashrc)"
fake() { # fake <dir> <version>: a ble.sh that announces itself, as the .bashrc will see it
  mkdir -p "$1"; printf '  _ble_init_version=%s\nBLE_VERSION=%s\necho FAKE_BLE_SOURCED\nble-attach() { echo FAKE_BLE_ATTACHED; }\n' "$2" "$2" > "$1/ble.sh"; }
oldnew() { # oldnew <label> <version>
  local h="$T/hv_$1"; mkdir -p "$h"; cp -r "$H/.config" "$h/"; fake "$h/fake" "$2"
  sed "s#/usr/share/blesh/ble.sh#$h/fake/ble.sh#" "$H/.bashrc" > "$h/.bashrc"
  SH_HOME="$h" session "v$1" 'echo MARK=$((6*7))'
}
oldnew 034 0.3.4;  [ "$(count v034 'FAKE_BLE_SOURCED')" = 0 ] && [ "$(count v034 'MARK=42')" -ge 1 ] && ok "ble.sh 0.3.4: not loaded, the shell works" || bad "0.3.4 was loaded or the shell broke" "$(head -5 "$T/out_v034.txt")"
oldnew 399 0.3.99; [ "$(count v399 'FAKE_BLE_SOURCED')" = 0 ] && ok "ble.sh 0.3.99: not loaded" || bad "0.3.99 was loaded"
oldnew 040 0.4.0-devel4+abc123; [ "$(count v040 'FAKE_BLE_SOURCED')" -ge 1 ] && [ "$(count v040 'FAKE_BLE_ATTACHED')" -ge 1 ] && ok "ble.sh 0.4.0-devel4: loaded and attached" || bad "0.4.0-devel4 not loaded" "$(head -5 "$T/out_v040.txt")"
oldnew 410 0.10.2; [ "$(count v410 'FAKE_BLE_ATTACHED')" -ge 1 ] && ok "ble.sh 0.10.2 (minor 10 > 4): loaded" || bad "0.10.2 not loaded"
oldnew 100 1.0.0;  [ "$(count v100 'FAKE_BLE_ATTACHED')" -ge 1 ] && ok "ble.sh 1.0.0: loaded" || bad "1.0.0 not loaded"

echo; echo "=== a nested shell (what 'chezmoi cd' starts) and re-sourcing ~/.bashrc"
session nested 'bash' 'echo INNER=$((_ble_attached+10))' 'exit' 'source ~/.bashrc' 'echo AFTER=$((40+2))'
# warnings BEFORE the re-source line = the nested shell; after it = ble.sh reloading under Omarchy's own `bind` calls (cosmetic, and
# ble.sh's documented way to reload is `exec bash`, not `source ~/.bashrc`)
awk '/source ~\/\.bashrc/{exit} {print}' "$T/out_nested.txt" > "$T/nested_only.txt"
[ "$(grep -c 'unsupported readline' "$T/nested_only.txt")" = 0 ] && ok "the nested shell ('chezmoi cd') starts with no warnings" || bad "nested readline warnings" "$(grep unsupported "$T/nested_only.txt" | head -4)"
[ "$(count nested 'INNER=11')" -ge 1 ] && ok "ble.sh attaches in the nested shell too" || bad "nested ble.sh" "$(tail -12 "$T/out_nested.txt")"
[ "$(count nested 'AFTER=42')" -ge 1 ] && ok "after 'source ~/.bashrc' the shell still responds (nothing recurses or hangs)" || bad "shell hung or broke after re-source" "$(tail -8 "$T/out_nested.txt")"
[ "$(count nested '❯')" -ge 4 ] && ok "starship prompt survives the nested shell and the re-source" || bad "starship lost" "$(grep -c '❯' "$T/out_nested.txt")"

echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL BLE CHECKS PASSED" || echo "SOME BLE CHECKS FAILED"
exit $fail
