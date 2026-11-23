#!/bin/bash
# Tests for dot_config/tmux/tmux.conf.tmpl and min-version.sh. The config is rendered by chezmoi into a throwaway
# HOME and loaded into a PRIVATE tmux server (own socket, sandboxed environment, never the real server).
#   .test/tmux.sh
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
command -v tmux >/dev/null 2>&1 || { echo "tmux not installed: skipped"; exit 0; }
T="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tmux-test.XXXXXX")"
[ -n "$T" ] && [ -d "$T" ] || { echo "could not create temp dir"; exit 2; }
SOCK="dftm$$"; S="tmux -L $SOCK"
trap '$S kill-server >/dev/null 2>&1; rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCK"; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/          /'; }
REAL_TMUX="$(command -v tmux)"

echo "=== min-version.sh against a table of tmux version strings (stand-in tmux -V)"
MV="$SRC/dot_config/tmux/executable_min-version.sh"
mvcase() { # mvcase <"tmux -V output"> <threshold> <expected exit>
  mkdir -p "$T/mv"; printf '#!/bin/sh\necho "%s"\n' "$1" > "$T/mv/tmux"; chmod +x "$T/mv/tmux"
  PATH="$T/mv:/usr/bin:/bin" sh "$MV" "$2"; local rc=$?
  [ $rc -eq "$3" ] && ok "'$1' vs >= $2 -> exit $rc" || bad "'$1' vs >= $2" "wanted exit $3, got $rc"; }
mvcase "tmux 3.8" 3.5 0;      mvcase "tmux 3.5" 3.5 0;     mvcase "tmux 3.4" 3.5 1
mvcase "tmux 3.6b" 3.6 0;     mvcase "tmux 3.3a" 3.4 1;    mvcase "tmux next-3.7" 3.5 0
mvcase "tmux 2.9a" 3.4 1;     mvcase "tmux 3.10" 3.9 0

apply() { # apply <label> <family> <env>: render the tmux dir into a throwaway home
  local h="$T/home_$1"; mkdir -p "$h/.config"
  printf '[data]\n  family = "%s"\n  env = "%s"\n' "$2" "$3" > "$T/cfg_$1.toml"
  chezmoi --source "$SRC" --config "$T/cfg_$1.toml" --persistent-state "$T/st_$1.db" --cache "$T/cache" --destination "$h" \
    apply --include=files,dirs "$h/.config/tmux" > "$T/ap_$1.log" 2>&1
  [ -z "$(grep -v 'config file template has changed' "$T/ap_$1.log")" ] || bad "[$1] chezmoi apply" "$(cat "$T/ap_$1.log")"; }
start() { # start <label> [PATH]: private server using that home's config; returns after it is up
  $S kill-server >/dev/null 2>&1; sleep 0.6
  env -i HOME="$T/home_$1" PATH="${2:-/usr/bin:/bin}" TERM=xterm LANG=C.UTF-8 SHELL=/bin/bash \
    $S -f "$T/home_$1/.config/tmux/tmux.conf" new-session -d -s t -x 200 -y 50 "bash --norc --noprofile"; sleep 0.5; }

check_config() { # check_config <label> <expect omarchy popup yes|no>
  local l=$1 want_popup=$2
  start "$l"
  local msgs; msgs=$($S show-messages 2>&1 | grep -iE 'unknown|invalid|error|ambiguous|too many|can.t find|not found' || true)
  [ -z "$msgs" ] && ok "[$l] the config loads without a single error message" || bad "[$l] load errors" "$msgs"
  [ "$($S show -gv prefix)" = "C-Space" ] && [ "$($S show -gv prefix2)" = "C-b" ] && ok "[$l] prefix is Ctrl+Space, Ctrl+b is the second prefix" || bad "[$l] prefix" "$($S show -gv prefix) / $($S show -gv prefix2)"
  for kv in "mouse on" "base-index 1" "status-position top" "history-limit 50000" "renumber-windows on" "focus-events on" "set-clipboard on" "allow-passthrough on" "extended-keys on" "extended-keys-format csi-u"; do
    set -- $kv; got=$($S show -gv "$1" 2>/dev/null); [ "$got" = "$2" ] && ok "[$l] $1 = $2" || bad "[$l] $1" "wanted $2, got [$got]"; done
  [ "$($S show -sv escape-time)" = 10 ] && ok "[$l] escape-time = 10" || bad "[$l] escape-time" "$($S show -sv escape-time)"
  $S show -sv terminal-features 2>/dev/null | grep -qF 'xterm*:extkeys' && ok "[$l] terminal-features has xterm*:extkeys (Shift+Enter on the Mac/Windows terminals)" || bad "[$l] extkeys feature" "$($S show -sv terminal-features)"
  $S list-keys -T root M-Enter 2>/dev/null | grep -q split-window && $S list-keys -T root C-M-Left 2>/dev/null | grep -q select-pane && $S list-keys -T root M-1 2>/dev/null | grep -q select-window && ok "[$l] Omarchy's Alt / Ctrl+Alt shortcuts are bound" || bad "[$l] alt shortcuts"
  $S list-keys -T prefix k 2>/dev/null | grep -q kill-window && ok "[$l] prefix+k is still kill-window (Omarchy's), matching herdr" || bad "[$l] prefix k" "$($S list-keys -T prefix k)"
  q=$($S list-keys -T prefix '?' 2>&1)
  if [ "$want_popup" = yes ]; then echo "$q" | grep -q 'omarchy-menu-tmux-keybindings' && ok "[$l] prefix+? is Omarchy's popup" || bad "[$l] prefix ?" "$q"
  else echo "$q" | grep -q 'omarchy-menu' && bad "[$l] prefix+? points at a command that does not exist here" "$q" || ok "[$l] prefix+? is tmux's own (no Omarchy-only command)"; fi
  $S list-keys -T prefix '{' 2>&1 | grep -q 'search-backward' && $S list-keys -T prefix '}' 2>&1 | grep -q 'search-forward' && ok "[$l] prefix+{ and prefix+} are the prompt-jump bindings" || bad "[$l] prompt-jump keys" "$($S list-keys -T prefix '{')"
  for tbl in copy-mode copy-mode-vi; do $S list-keys -T $tbl '[' 2>&1 | grep -q search-backward && $S list-keys -T $tbl ']' 2>&1 | grep -q search-forward && ok "[$l] [ and ] hop between prompts in $tbl" || bad "[$l] $tbl [ ]"; done
}

echo; echo "=== Omarchy (env=omarchy)"; apply om arch omarchy; check_config om yes
echo; echo "=== plain Arch / Arch WSL / Ubuntu / Mac (env=native)"; apply na arch native; check_config na no

echo; echo "=== prompt-jump actually works (a real attached client, keys sent through tmux's key tables)"
start om
# send-keys without -K writes straight to the pane and never reaches tmux's key tables, so attach a real client in a
# pseudo-terminal (script, with a hard timeout so nothing can linger) and send keys to IT with -K. script(1) quits
# when its stdin reaches EOF, so its stdin is a FIFO that this test keeps open (fd 9) and closes when done.
mkfifo "$T/hold"
( timeout 60 script -qec "env -i HOME=$T/home_om PATH=/usr/bin:/bin TERM=xterm-256color LANG=C.UTF-8 $S attach -t t" /dev/null <"$T/hold" >/dev/null 2>&1 ) &
CLPID=$!
exec 9>"$T/hold"
client=""; for _ in $(seq 1 30); do client=$($S list-clients -F '#{client_name}' 2>/dev/null | head -1); [ -n "$client" ] && break; sleep 0.2; done
if [ -z "$client" ]; then bad "could not attach a test client"
else
  $S send-keys -t t "clear; printf 'a\\n❯ cmd1\\nout1\\n❯ cmd2\\nout2\\n❯ cmd3\\nend\\n'" Enter; sleep 0.6
  jump() { $S send-keys -K -c "$client" C-Space; sleep 0.15; $S send-keys -K -c "$client" "$1"; sleep 0.35; $S display-message -p -t t '#{pane_in_mode}|#{copy_cursor_line}'; }
  r1=$(jump '{'); r2=$(jump '{'); r3=$(jump '}')
  case "$r1" in "1|❯ cmd3"*) ok "prefix+{ enters copy mode on the previous prompt (cmd3)";; *) bad "first {" "$r1";; esac
  case "$r2" in "1|❯ cmd2"*) ok "prefix+{ again goes one prompt further back (cmd2)";; *) bad "second {" "$r2";; esac
  case "$r3" in "1|❯ cmd3"*) ok "prefix+} comes forward to the next prompt (cmd3)";; *) bad "}" "$r3";; esac
  $S send-keys -K -c "$client" q; sleep 0.2
fi
exec 9>&-          # EOF for script(1): the test client goes away
$S kill-server >/dev/null 2>&1; wait $CLPID 2>/dev/null

echo; echo "=== older tmux: the version guards must keep the two newer options OFF (stand-in tmux -V says 3.3)"
mkdir -p "$T/old"; printf '#!/bin/sh\nif [ "$1" = "-V" ]; then echo "tmux 3.3"; else exec "%s" "$@"; fi\n' "$REAL_TMUX" > "$T/old/tmux"; chmod +x "$T/old/tmux"
start om "$T/old:/usr/bin:/bin"
[ "$($S show -gv allow-passthrough)" = off ] && ok "allow-passthrough stays off (needs tmux 3.4)" || bad "allow-passthrough was set on an 'old' tmux" "$($S show -gv allow-passthrough)"
[ "$($S show -gv extended-keys-format)" = xterm ] && ok "extended-keys-format stays at its default (needs tmux 3.5)" || bad "extended-keys-format was set on an 'old' tmux" "$($S show -gv extended-keys-format)"
[ "$($S show -gv prefix)" = "C-Space" ] && ok "everything else still loads (prefix is Ctrl+Space)" || bad "rest of config" "$($S show -gv prefix)"
msgs=$($S show-messages 2>&1 | grep -iE 'unknown|invalid|error' || true); [ -z "$msgs" ] && ok "and still no error messages" || bad "errors on the 'old' tmux" "$msgs"
$S kill-server >/dev/null 2>&1

echo; echo "=== drift from Omarchy's own file (informational: Omarchy may update it)"
rendered="$(chezmoi --source "$SRC" --config "$T/cfg_om.toml" --persistent-state "$T/st_om.db" --cache "$T/cache" execute-template < "$SRC/dot_config/tmux/tmux.conf.tmpl" 2>/dev/null)"
if [ -r /usr/share/omarchy/config/tmux/tmux.conf ]; then
  missing=$(diff -B <(cat /usr/share/omarchy/config/tmux/tmux.conf) <(printf '%s\n' "$rendered") | grep '^<' | grep -vE 'allow-passthrough on|extended-keys-format csi-u' | wc -l)
  [ "$missing" = 0 ] && printf '  INFO  every line of Omarchy'"'"'s current tmux.conf is present in ours, except the two we guard\n' || printf '  INFO  %s line(s) of Omarchy'"'"'s current tmux.conf are missing or changed in ours: Omarchy updated its file, so review dot_config/tmux/tmux.conf.tmpl\n' "$missing"
else echo "  INFO  Omarchy's tmux.conf not present on this machine: drift check skipped"; fi

echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL TMUX CHECKS PASSED" || echo "SOME TMUX CHECKS FAILED"
exit $fail
