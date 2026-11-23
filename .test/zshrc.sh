#!/bin/bash
# End-to-end test of dot_zshrc (+ the shared files it sources) for the zsh machines (Ubuntu, Mac): applies the
# repo into a THROWAWAY home with an isolated chezmoi config (files and dirs only, never run_ scripts), then runs a
# real interactive zsh and checks what it did. Needs zsh.
#   .test/zshrc.sh
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
command -v zsh >/dev/null 2>&1 || { echo "zsh not installed: skipped"; exit 0; }
T="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-zshrc-test.XXXXXX")"
[ -n "$T" ] && [ -d "$T" ] || { echo "could not create temp dir"; exit 2; }
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/          /'; }

H="$T/home"; mkdir -p "$H/.config" "$H/.local/bin" "$H/bin"
printf '[data]\n  family = "debian"\n  env = "native"\n' > "$T/cfg.toml"
chezmoi --source "$SRC" --config "$T/cfg.toml" --persistent-state "$T/st.db" --cache "$T/cache" --destination "$H" \
  apply --include=files,dirs "$H/.zshrc" "$H/.config/shell" > "$T/apply.log" 2>&1
[ -z "$(grep -v 'config file template has changed' "$T/apply.log")" ] && ok "chezmoi applied .zshrc and the shared files cleanly" || bad "apply" "$(cat "$T/apply.log")"
[ -f "$H/.zshrc" ] && ok ".zshrc deployed for family=debian" || bad ".zshrc missing"

# Interactive zsh needs a real terminal (without one fzf's zsh integration prints "can't change option: zle"
# and a stray read from an inherited stdin can hang), so run it in a pseudo-terminal via script(1) with stdin closed.
# The snippet goes through a file so no quoting is needed. TMUX=1 only keeps the fastfetch banner (replaced in
# the next commit) out of the output.
command -v script >/dev/null 2>&1 || { echo "script(1) not available: skipped"; exit 0; }
zrun() {
  printf '%s\n' "$1" > "$T/snippet.zsh"
  timeout 40 script -qec "env -i HOME=$H PATH=/usr/bin:/bin TERM=xterm USER=tester LANG=C.UTF-8 TMUX=1 MISE_DATA_DIR=$H/.mise MISE_STATE_DIR=$H/.mise MISE_CONFIG_DIR=$H/.mise MISE_CACHE_DIR=$H/.mise zsh -i -c 'source $T/snippet.zsh'" /dev/null </dev/null 2>&1 | tr -d '\r'
}

out=$(zrun 'echo END'); [ "$out" = END ] && ok "interactive zsh starts, prints nothing else (no errors, no banner)" || bad "startup output" "$out"

out=$(zrun 'echo "ED=$EDITOR"; echo "VIS=$VISUAL"; echo "PATH=$PATH"; echo "AS=$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE"; echo "FZF=$FZF_DEFAULT_OPTS"')
echo "$out" | grep -q '^ED=nvim$' && echo "$out" | grep -q '^VIS=nvim$' && ok "EDITOR and VISUAL are nvim" || bad "editor vars" "$out"
# (mise activate, later in .zshrc, puts its own wrapper dir in front, as it always did; what matters is that
# the user dirs from common.sh come before the system ones.)
p=$(echo "$out" | sed -n 's/^PATH=//p'); case ":$p:" in
  *":$H/.local/bin:"*":/usr/bin:"*) ok "~/.local/bin is on PATH ahead of the system directories (common.sh)" ;;
  *) bad "PATH order" "$p" ;; esac
case ":$p:" in *":$H/bin:"*) ok "~/bin is on PATH too (it exists in this home)" ;; *) bad "~/bin missing from PATH" "$p" ;; esac
echo "$out" | grep -q '^AS=fg=8$' && ok "autosuggestion colour is ANSI bright black (fg=8)" || bad "autosuggest style" "$(echo "$out" | grep AS=)"
echo "$out" | grep -q '^FZF=--height 40% --layout=reverse --border$' && ok "fzf options carry no hex colours" || bad "fzf opts" "$(echo "$out" | grep FZF=)"

out=$(zrun 'for v in THEME_MODE DELTA_FEATURES STARSHIP_CONFIG LS_COLORS; do [[ -n ${(P)v} ]] && echo "SET:$v"; done; whence -w _theme_apply _theme_guess _theme_widget_dark; echo END')
echo "$out" | grep -q '^SET:' && bad "leftover theming variables" "$out" || ok "no THEME_MODE / DELTA_FEATURES / STARSHIP_CONFIG / LS_COLORS leftovers"
[ "$(echo "$out" | grep -c ': none$')" = 3 ] && ok "the light/dark theming functions are gone" || bad "theming functions still defined" "$out"
grep -qE 'secrets|vivid|THEME_MODE|DELTA_FEATURES|rose-pine' "$H/.zshrc" && bad ".zshrc still mentions removed things" "$(grep -nE 'secrets|vivid|THEME_MODE|DELTA_FEATURES|rose-pine' "$H/.zshrc")" || ok ".zshrc no longer mentions secrets, vivid, THEME_MODE, DELTA_FEATURES or rose-pine"

out=$(zrun 'for a in ls ll la lt cd g gcm gcam d t h ff eff tf; do alias $a >/dev/null || echo "NOALIAS:$a"; done; for f in zd ga gd tdl tds tdlm tsl hdl hds hdlm hsl ssh fip dip lip compress; do whence -w $f | grep -q function || echo "NOFUNC:$f"; done; [[ $(alias -g) == *"N""V="* ]] && echo GLOBALOK; echo END')
echo "$out" | grep -q -e NOALIAS -e NOFUNC && bad "missing aliases/functions" "$out" || ok "all shared aliases and functions are defined in zsh"
echo "$out" | grep -q '^GLOBALOK$' && ok "the zsh-only global alias (pipe into nvim) is still defined" || bad "global nvim alias" "$out"

command -v starship >/dev/null && { out=$(zrun 'print -l $precmd_functions'); echo "$out" | grep -q starship && ok "starship is initialised" || bad "starship precmd" "$out"; }
command -v zoxide >/dev/null && { out=$(zrun 'whence -w z'); echo "$out" | grep -q 'function' && ok "zoxide is initialised (z exists)" || bad "zoxide" "$out"; }
out=$(zrun 'print -l $precmd_functions $preexec_functions'); echo "$out" | grep -q '_osc133_precmd' && echo "$out" | grep -q '_osc133_preexec' && ok "OSC 133 prompt marks are hooked" || bad "osc133" "$out"
for t in atuin direnv; do command -v $t >/dev/null || ok "$t absent here: its guarded line was skipped without an error (see the clean startup above)"; done

# startup time (median of 5, ms); informational
s=(); for i in 1 2 3 4 5; do a=$EPOCHREALTIME; zrun 'exit' >/dev/null; b=$EPOCHREALTIME; s+=($(awk -v a=$a -v b=$b 'BEGIN{printf "%d",(b-a)*1000}')); done
printf '  INFO  interactive zsh startup, median of 5: %s ms\n' "$(printf '%s\n' "${s[@]}" | sort -n | sed -n 3p)"

echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL ZSHRC CHECKS PASSED" || echo "SOME ZSHRC CHECKS FAILED"
exit $fail
