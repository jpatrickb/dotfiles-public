#!/bin/bash
# Tests for the terminal configs: the Otty files (Mac only), the WSL->Windows Noctty copy script (run against a
# FAKE Windows drive with stand-ins for cmd.exe and wslpath), and the WezTerm retirement. Everything runs in throwaway directories with isolated chezmoi state.
#   .test/terminals.sh
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-terminals-test.XXXXXX")"
[ -n "$T" ] && [ -d "$T" ] || { echo "could not create temp dir"; exit 2; }
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/          /'; }

apply() { # apply <label> <family> <env> <target subpath...>: render into a throwaway home
  local h="$T/home_$1"; mkdir -p "$h/.config"; local l=$1 f=$2 e=$3; shift 3
  printf '[data]\n  family = "%s"\n  env = "%s"\n' "$f" "$e" > "$T/cfg_$l.toml"
  local targets=(); for s in "$@"; do targets+=("$h/$s"); done
  chezmoi --source "$SRC" --config "$T/cfg_$l.toml" --persistent-state "$T/st_$l.db" --cache "$T/cache" --destination "$h" \
    apply --include=files,dirs "${targets[@]}" > "$T/ap_$l.log" 2>&1
  [ -z "$(grep -v 'config file template has changed' "$T/ap_$l.log")" ] || bad "[$l] apply" "$(cat "$T/ap_$l.log")"; }

echo "=== Otty files: where they are installed"
for spec in "mac mac native yes" "wsl arch wsl no" "om arch omarchy no" "ub debian native no" "pa arch native no"; do set -- $spec
  apply $1 $2 $3 .config
  all=1; for f in config.toml themes/omarchy.ottytheme; do [ -f "$T/home_$1/.config/otty/$f" ] || all=0; done
  if [ "$4" = yes ]; then [ $all = 1 ] && ok "[$1] Otty config.toml and the theme file are installed" || bad "[$1] Otty files missing" "$(ls -R "$T/home_$1/.config/otty" 2>&1 | head)"
  else [ ! -e "$T/home_$1/.config/otty" ] && ok "[$1] no Otty files (this machine uses another terminal)" || bad "[$1] Otty files installed where they should not be"; fi
  # Noctty is the Windows terminal for now: its files belong on WSL machines and nowhere else
  if [ "$1" = wsl ]; then [ -f "$T/home_$1/.config/noctty/config.ghostty" ] && [ -f "$T/home_$1/.config/noctty/omarchy-theme.conf" ] && ok "[wsl] Noctty config and palette are installed (Noctty is the Windows terminal)" || bad "[wsl] Noctty files missing"
  else [ ! -e "$T/home_$1/.config/noctty" ] && ok "[$1] no Noctty files" || bad "[$1] Noctty files installed outside WSL"; fi
done

echo; echo "=== the Mac's Otty config.toml (tracked as-is; the shared settings were folded into it)"
F="$T/home_mac/.config/otty/config.toml"
grep -qE '^include *=' "$F" && bad "config.toml still includes another file" "$(grep -n '^include' "$F")" || ok "no include line: config.toml is the single source"
grep -qxF 'font-family = "JetBrainsMono Nerd Font"' "$F" && grep -qxE 'copy-on-select = true' "$F" && ok "Nerd Font and copy-on-select are set" || bad "font/copy-on-select" "$(grep -n -E 'font|copy' "$F")"
grep -qxE 'macos-option-as-alt = left' "$F" && ok "left Option acts as Alt (tmux/herdr Alt shortcuts)" || bad "option-as-alt"
grep -qxF 'keybind = shift+enter=csi:13;2u' "$F" && grep -qxF 'keybind = alt+shift+enter=csi:13;4u' "$F" && ok "the two CSI-u keybinds are there" || bad "CSI-u keybinds" "$(grep keybind "$F")"
grep -qxE 'theme *= *"?omarchy"?' "$F" && bad "the Mac config selects the Omarchy theme" || ok "the Mac keeps its own theme (not the Omarchy one)"
# Otty: a comment must be on its own line (a trailing # on a keybind line becomes part of the action)
grep -vE '^\s*(#|$)' "$F" | grep -qE '^[a-z-]+ = [^"].*\s#|^[a-z-]+ = ".*"\s+#' && bad "a trailing comment follows a value" "$(grep -vE '^\s*(#|$)' "$F" | grep -E '\s#')" || ok "no trailing comments after values"
dups=$(grep -vE '^\s*(#|$|keybind|open-with-app)' "$F" | cut -d' ' -f1 | sort | uniq -d); [ -z "$dups" ] && ok "no setting is repeated (keybind and open-with-app may repeat)" || bad "duplicated settings: $dups"
[ ! -e "$SRC/dot_config/otty/dotfiles.toml.tmpl" ] && [ ! -e "$SRC/dot_config/otty/create_config.toml" ] && ok "the old seed and shared-layer files are gone from the source" || bad "old Otty files remain"
echo; echo "=== the generated Omarchy theme file (kept for the theme sync)"
python3 -I - "$SRC/dot_config/otty/themes/omarchy.ottytheme" <<'PY' && ok "the theme file's name slug (omarchy) matches the file name and 'theme = omarchy'" || bad "theme slug"
import tomllib,sys,re,os
d=tomllib.load(open(sys.argv[1],'rb'))
slug=re.sub(r'[^a-z0-9]+','-',d['meta']['name'].lower()).strip('-')
assert slug=='omarchy' and os.path.basename(sys.argv[1])=='omarchy.ottytheme', slug
assert len(d['terminal']['palette'])==16
PY

echo; echo "=== stand-ins for the Windows side (a fake drive, cmd.exe and wslpath)"
NT="$SRC/run_copy-noctty-to-windows.sh"
WIN="$T/winc"; mkdir -p "$WIN/Users/tester" "$WIN/Users/tester/AppData/Roaming" "$WIN/Users/tester/AppData/Local" "$T/stubs"
cat > "$T/stubs/cmd.exe" <<'EOF'
#!/bin/sh
# stand-in: answers `cmd.exe /c "echo %VAR%"` with CRLF like the real thing (LOCALAPPDATA before APPDATA: substring)
case "$*" in
  *LOCALAPPDATA*) printf 'C:\\Users\\tester\\AppData\\Local\r\n' ;;
  *APPDATA*)      printf 'C:\\Users\\tester\\AppData\\Roaming\r\n' ;;
  *USERPROFILE*)  [ -n "${FAKE_NO_PROFILE:-}" ] && printf '%%USERPROFILE%%\r\n' || printf 'C:\\Users\\tester\r\n' ;;
esac
EOF
cat > "$T/stubs/wslpath" <<EOF
#!/bin/sh
printf '%s' "\$1" | sed -e 's#^C:##' -e 's#\\\\#/#g' -e 's#^#$WIN#'
EOF
chmod +x "$T/stubs/cmd.exe" "$T/stubs/wslpath"
WH="$T/home_mac"   # a home that has Otty files; the Noctty section switches to a fresh WSL home
runw() { env -i HOME="$WH" PATH="$T/stubs:/usr/bin:/bin" DOTFILES_WIN_MOUNT="$WIN" "$@"; }

echo; echo "=== run_copy-noctty-to-windows.sh (the Windows terminal): config plus the generated palette"
apply wsl2 arch wsl .config; WH="$T/home_wsl2"     # a fresh WSL home
ND="$WIN/Users/tester/AppData/Local/noctty"
out=$(runw bash "$NT" 2>&1); rc=$?
[ $rc -eq 0 ] && cmp -s "$ND/config.ghostty" "$T/home_wsl2/.config/noctty/config.ghostty" && ok "config.ghostty is copied to %LOCALAPPDATA%\\noctty" || bad "noctty config copy" "rc=$rc $out"
cmp -s "$ND/omarchy-theme.conf" "$T/home_wsl2/.config/noctty/omarchy-theme.conf" && ok "the generated palette is copied next to it (config-file = omarchy-theme.conf resolves)" || bad "palette not copied" "$(ls "$ND")"
echo '# edited on Windows' >> "$ND/config.ghostty"; runw bash "$NT" >/dev/null 2>&1
grep -q 'edited on Windows' "$ND/config.ghostty.bak" && ok "a Windows-side edit is saved as config.ghostty.bak before being overwritten" || bad "no .bak"
N="$SRC/dot_config/noctty/config.ghostty"
grep -qxF 'config-file = omarchy-theme.conf' "$N" && ! grep -qE '^theme *=' "$N" && ok "config.ghostty includes the generated palette and no longer sets a built-in Rose Pine theme" || bad "noctty theme lines" "$(grep -nE '^(theme|config-file)' "$N")"
grep -qxF 'keybind = shift+enter=csi:13;2u' "$N" && grep -qxF 'keybind = alt+shift+enter=csi:13;4u' "$N" && grep -qxF 'command = wsl.exe' "$N" && ok "Noctty has the CSI-u keybinds and still opens WSL" || bad "noctty keybinds/command"
grep -vE '^\s*(#|$)' "$N" | grep -qE '\s#' && bad "trailing comment in config.ghostty" || ok "no trailing comments in config.ghostty (Ghostty would make them part of the value)"

echo; echo "=== WezTerm is retired"
[ ! -e "$SRC/dot_config/wezterm" ] && [ ! -e "$SRC/run_copy-wezterm-to-windows.sh" ] && ok "wezterm.lua and its copy script are gone from the source" || bad "wezterm files remain"
grep -qxF '.config/wezterm/wezterm.lua' "$SRC/.chezmoiremove" && ok "the WSL copy is listed in .chezmoiremove" || bad "chezmoiremove entry"
mkdir -p "$T/home_wz/.config/wezterm"; echo x > "$T/home_wz/.config/wezterm/wezterm.lua"; printf '[data]\n  family = "arch"\n  env = "wsl"\n' > "$T/cfg_wz.toml"
wzout=$(chezmoi --source "$SRC" --config "$T/cfg_wz.toml" --persistent-state "$T/st_wz.db" --cache "$T/cache" --destination "$T/home_wz" apply --dry-run --verbose 2>&1)
grep -q 'wezterm/wezterm.lua' <<<"$wzout" && ok "chezmoi would remove a leftover wezterm.lua (dry run)" || bad "stale wezterm.lua would not be removed"

echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL TERMINAL CHECKS PASSED" || echo "SOME TERMINAL CHECKS FAILED"
exit $fail
