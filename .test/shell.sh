#!/bin/bash
# Tests for dot_config/shell/common.sh and functions.sh, run under every shell given (default: bash and zsh
# when installed). Everything runs in a clean environment (env -i) with a throwaway HOME, so nothing real is
# touched: tmux uses its own socket, `herdr` and `ssh` are stand-ins that log their calls, and git/mise state
# lives in the temp dir.
#   .test/shell.sh            all installed shells
#   .test/shell.sh bash       just one
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
SH_DIR="$SRC/dot_config/shell"
T="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-shell-test.XXXXXX")"
[ -n "$T" ] && [ -d "$T" ] || { echo "could not create temp dir"; exit 2; }
# Cleanup: stop the private tmux server and delete its socket file (tmux can leave it behind when the server
# is killed while another is starting), then the temp dir.
trap 'tmux -L "dfst$$" kill-server >/dev/null 2>&1; rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/dfst$$"; rm -rf "$T"' EXIT
fail=0; pass=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/          /'; }
check() { # check "label" 'command that must succeed'
  local out; if out=$(eval "$2" 2>&1); then ok "$1"; else bad "$1" "$out"; fi; }

mkdir -p "$T/home" "$T/stubs" "$T/proj/a" "$T/proj/b"
# Stand-in herdr: logs every call, and answers `pane split` / `tab create` with a fresh fake pane id.
cat > "$T/stubs/herdr" <<EOF
#!/bin/bash
echo "\$*" >> "$T/herdr.log"
n=\$(( \$(cat "$T/herdr.n" 2>/dev/null || echo 0) + 1 )); echo \$n > "$T/herdr.n"
case "\$1 \$2" in
  "pane split") echo "{\"result\":{\"pane\":{\"pane_id\":\"p\$n\"}}}" ;;
  "tab create") echo "{\"result\":{\"root_pane\":{\"pane_id\":\"r\$n\"}}}" ;;
esac
exit 0
EOF
# Stand-in ssh: exits with \$FAKE_SSH_RC and records that it ran. `ssh -G` (which only prints the effective
# configuration and never connects) is passed through to the REAL ssh, because ssh()'s reconnect safety check
# relies on its answer.
REAL_SSH="$(command -v ssh || true)"
cat > "$T/stubs/ssh" <<EOF
#!/bin/bash
if [ "\$1" = "-G" ]; then exec "$REAL_SSH" "\$@"; fi
echo "ssh \$*" >> "$T/ssh.log"
exit "\${FAKE_SSH_RC:-0}"
EOF
chmod +x "$T/stubs/herdr" "$T/stubs/ssh"
CLEAN_ENV=(env -i HOME="$T/home" PATH="$T/stubs:/usr/bin:/bin" TERM=xterm USER=tester LANG=C.UTF-8)

runsh() { # runsh <shell> '<script>'  : interactive (aliases expand), no rc files, clean env
  case "$1" in
    bash) "${CLEAN_ENV[@]}" bash --norc --noprofile -i -c "$2" ;;
    zsh)  "${CLEAN_ENV[@]}" zsh -f -i -c "$2" ;;
  esac; }

shells=("$@"); [ ${#shells[@]} -gt 0 ] || { shells=(bash); command -v zsh >/dev/null 2>&1 && shells+=(zsh); }
for sh in "${shells[@]}"; do
  command -v "$sh" >/dev/null 2>&1 || { echo "== $sh: not installed, skipped"; continue; }
  echo; echo "=================== $sh ($("$sh" --version 2>&1 | head -1 | cut -c1-60))"
  L=". '$SH_DIR/common.sh' && . '$SH_DIR/functions.sh'"
  case "$sh" in bash) NORC="--norc --noprofile" ;; zsh) NORC="-f" ;; esac
  val() { runsh "$sh" "$L; $1" 2>/dev/null; }            # run a snippet with both files loaded, print its output

  echo "-- loading"
  out=$(runsh "$sh" "$L; echo LOADED" 2>&1); case "$out" in *LOADED*) ok "common.sh + functions.sh load" ;; *) bad "load" "$out";; esac
  err=$(runsh "$sh" "$L" 2>&1 >/dev/null | grep -v -e 'no job control' -e 'cannot set terminal process group' -e 'Inappropriate ioctl' || true)
  [ -z "$err" ] && ok "no error output while loading" || bad "stderr while loading" "$err"
  for f in zd sff ga gd tdl tds tdlm tsl hdl hds hdlm hsl ssh fip dip lip compress _ssh_interactive; do
    check "function defined: $f" "runsh $sh \"$L; type $f\" >/dev/null"
  done
  for a in ll la lt g gcm gcam d t h tf ff eff; do
    check "alias defined: $a" "runsh $sh \"$L; alias $a\" >/dev/null"
  done
  if command -v eza >/dev/null 2>&1; then
    case "$(val 'alias ls')" in *eza*) ok "ls is eza" ;; *) bad "ls alias" "$(val 'alias ls')" ;; esac
  fi
  [ "$(val 'echo $EDITOR')" = nvim ] && ok "EDITOR=nvim" || bad "EDITOR" "$(val 'echo $EDITOR')"

  echo "-- _dotfiles_quote round-trips awkward words"
  for w in "plain" "with space" "it's" 'dq"uote' 'back\slash' 'dollar$HOME' 'star*'; do
    got=$("${CLEAN_ENV[@]}" W="$w" "$sh" $NORC -c ". '$SH_DIR/functions.sh'; eval \"x=\$(_dotfiles_quote \"\$W\")\"; printf '%s' \"\$x\"")
    [ "$got" = "$w" ] && ok "quote: $w" || bad "quote: $w" "got [$got]"
  done

  echo "-- _ssh_interactive (which ssh invocations may auto-reconnect)"
  while IFS='|' read -r want args; do
    [ -z "$want" ] && continue
    out=$(runsh "$sh" "$L; _ssh_interactive $args && echo YES || echo NO" 2>/dev/null | tail -1)
    [ "$out" = "$want" ] && ok "ssh $args -> $want" || bad "ssh $args" "wanted $want, got $out"
  done <<'CASES'
YES|host
YES|-p 2222 host
YES|-p2222 host
YES|-l user host
YES|-J jump host
YES|-- host
NO|host uptime
NO|
NO|-o RemoteCommand=ls host
CASES

  echo "-- ssh() wrapper with a stand-in ssh (stdout is not a terminal here, so no reconnect loop)"
  for rc in 0 1 255; do
    : > "$T/ssh.log"
    out=$("${CLEAN_ENV[@]}" FAKE_SSH_RC=$rc "$sh" $NORC -c ". '$SH_DIR/functions.sh'; ssh somehost; echo RC=\$?" 2>&1 | tail -1)
    runs=$(grep -c '^ssh somehost' "$T/ssh.log")
    [ "$out" = "RC=$rc" ] && [ "$runs" = 1 ] && ok "exit $rc passed through, ssh ran once" || bad "ssh wrapper rc=$rc" "got [$out], ssh ran $runs times"
  done

  echo "-- git worktrees: ga"
  W="$T/wt_$sh"; mkdir -p "$W/repo"
  out=$(cd "$W/repo" && git init -q . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init \
        && "${CLEAN_ENV[@]}" GIT_CONFIG_GLOBAL=/dev/null MISE_DATA_DIR="$T/mise" MISE_STATE_DIR="$T/mise" MISE_CONFIG_DIR="$T/mise" MISE_CACHE_DIR="$T/mise" PATH="$PATH" \
           "$sh" $NORC -c ". '$SH_DIR/functions.sh'; ga feat >/dev/null 2>&1; pwd; git branch --show-current" 2>&1 | tail -2)
  [ "$(echo "$out" | head -1)" = "$W/repo--feat" ] && [ "$(echo "$out" | tail -1)" = feat ] && ok "ga: created ../repo--feat on branch feat and moved into it" || bad "ga" "$out"

  if command -v tmux >/dev/null 2>&1; then
    echo "-- tmux layouts, inside a private tmux server (own socket) running $sh"
    SOCK="dfst$$"; S="tmux -L $SOCK -f /dev/null"
    mkshell() { echo "$sh $NORC"; }
    runpane() { # runpane <commands...> : run in a fresh single-pane session, wait for the marker, leave server up
      $S kill-server >/dev/null 2>&1; sleep 0.6   # let the old server release the socket, or the next one dies at startup
      rm -f "$T/marker"
      # The server (and so every window it opens later, e.g. by tdlm) must NOT inherit the real environment: with
      # the real HOME those new windows would source the real ~/.bashrc and run Omarchy's own tdl (and nvim).
      env -i HOME="$T/home" PATH="/usr/bin:/bin" TERM=xterm LANG=C.UTF-8 EDITOR=true SHELL="$(command -v "$sh")" \
        $S new-session -d -s t -x 200 -y 60 -c "$T/proj" "$(mkshell)"; sleep 0.4
      $S send-keys -t t ". '$SH_DIR/functions.sh'; export EDITOR=true; cd '$T/proj'; $1; echo done > '$T/marker'" Enter
      for _ in $(seq 1 40); do [ -f "$T/marker" ] && break; sleep 0.25; done; sleep 0.3; }
    first_pane() { $S list-panes -t t:0 -F '#{pane_id}' | head -1; }
    runpane "tdl 'echo ai'"
    n=$($S list-panes -t t:0 | wc -l); active=$($S list-panes -t t:0 -F '#{pane_id} #{pane_active}' | awk '$2==1{print $1}')
    [ "$n" = 3 ] && ok "tdl: editor + ai + terminal = 3 panes" || bad "tdl pane count" "$n panes"
    [ "$active" = "$(first_pane)" ] && ok "tdl: focus returns to the editor pane (Omarchy's original named an unset variable)" || bad "tdl focus" "active=$active first=$(first_pane)"
    runpane "tds"
    [ "$($S list-panes -t t:0 | wc -l)" = 4 ] && ok "tds: 4 panes" || bad "tds panes" "$($S list-panes -t t:0 | wc -l)"
    runpane "tsl 4 'echo swarm'"
    n=$($S list-panes -t t:0 | wc -l); active=$($S list-panes -t t:0 -F '#{pane_id} #{pane_active}' | awk '$2==1{print $1}')
    [ "$n" = 4 ] && ok "tsl 4: four panes" || bad "tsl pane count" "$n"
    [ "$active" = "$(first_pane)" ] && ok "tsl: focus on the first pane (needs 0-based indexing under zsh too)" || bad "tsl focus" "active=$active first=$(first_pane)"
    runpane "tdlm 'echo ai'"; sleep 1.5
    # tdlm renames the session to the directory name, so count windows across all sessions
    [ "$($S list-windows -a -F x | wc -l)" = 2 ] && ok "tdlm: one window per subdirectory (a, b)" || bad "tdlm windows" "$($S list-windows -a -F x | wc -l)"
    $S kill-server >/dev/null 2>&1
  else echo "-- tmux not installed: layout tests skipped"; fi

  echo "-- herdr layouts against the logging stand-in"
  hs() { : > "$T/herdr.log"; echo 0 > "$T/herdr.n"
    "${CLEAN_ENV[@]}" HERDR_PANE_ID=P0 HERDR_TAB_ID=T0 HERDR_WORKSPACE_ID=W0 EDITOR=true PATH="$T/stubs:/usr/bin:/bin" \
      "$sh" $NORC -c "cd '$T/proj'; . '$SH_DIR/functions.sh'; $1" >/dev/null 2>&1; }
  hs "hdl 'echo ai'"
  [ "$(grep -c '^pane run' "$T/herdr.log")" = 2 ] && grep -q '^pane run P0 true \.' "$T/herdr.log" && ok "hdl: runs the editor in the original pane and the AI in the new one" || bad "hdl" "$(cat "$T/herdr.log")"
  hs "hds"; [ "$(grep -c '^pane run' "$T/herdr.log")" = 3 ] && ok "hds: three panes started" || bad "hds" "$(cat "$T/herdr.log")"
  for count in 1 2 4 6 9; do
    hs "hsl $count 'echo swarm'"; runs=$(grep -c "^pane run .* echo swarm" "$T/herdr.log")
    ids=$(grep "^pane run .* echo swarm" "$T/herdr.log" | awk '{print $3}' | sort | uniq | wc -l)
    [ "$runs" = "$count" ] && [ "$ids" = "$count" ] && ok "hsl $count: $count distinct panes each started once" || bad "hsl $count" "runs=$runs distinct=$ids; $(tr '\n' ';' < "$T/herdr.log" | cut -c1-200)"
  done
  hs "hdlm 'echo ai'"
  [ "$(grep -c '^tab create' "$T/herdr.log")" = 1 ] && grep -q 'cd .*proj/a' "$T/herdr.log" && ok "hdlm: first subdirectory reuses this tab, the second gets a new tab" || bad "hdlm" "$(cat "$T/herdr.log")"

  if [ "$(uname -s)" = Linux ] && command -v inotifywait >/dev/null 2>&1 && command -v rsync >/dev/null 2>&1 && command -v setsid >/dev/null 2>&1; then
    echo "-- rsync-on-change watchers: rsw / lsw / dsw (local directories)"
    mkdir -p "$T/rs_src" "$T/rs_dst"
    out=$("${CLEAN_ENV[@]}" PATH="/usr/bin:/bin" XDG_RUNTIME_DIR="$T" "$sh" $NORC -c ". '$SH_DIR/functions.sh'; rsw '$T/rs_src' '$T/rs_dst'; sleep 1; echo hello > '$T/rs_src/f.txt'; sleep 2; lsw; dsw; sleep 0.5; lsw" 2>&1)
    [ -f "$T/rs_dst/f.txt" ] && ok "rsw: a new file was synced on change" || bad "rsw sync" "$out"
    echo "$out" | grep -q 'Stopped watch' && echo "$out" | tail -1 | grep -q 'No active watches' && ok "lsw lists it, dsw stops it" || bad "lsw/dsw" "$out"
  else echo "-- rsw/lsw/dsw skipped (need Linux + inotify-tools + rsync + setsid)"; fi
done

echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL SHELL CHECKS PASSED" || echo "SOME SHELL CHECKS FAILED"
exit $fail
