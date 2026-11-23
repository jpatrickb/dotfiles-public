#!/bin/bash
# End-to-end test of modify_dot_bashrc and the bash side of dot_config/shell/: applies the repo into a
# THROWAWAY home (chezmoi --destination, isolated config/state; only files and dirs, never run_ scripts) for
# each machine type, then checks the result and what a real interactive bash does with it.
#   .test/bashrc.sh
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bashrc-test.XXXXXX")"
[ -n "$T" ] && [ -d "$T" ] || { echo "could not create temp dir"; exit 2; }
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/          /'; }

# Seeds: Omarchy's own skeleton .bashrc (what a fresh Omarchy user gets), and a typical stock Arch one.
OMARCHY_SEED="$T/seed_omarchy"; [ -r /etc/skel/.bashrc ] && cp /etc/skel/.bashrc "$OMARCHY_SEED" || cat > "$OMARCHY_SEED" <<'EOF'
[[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] && source /usr/share/omarchy/default/bash/env-bootstrap
[[ $- != *i* ]] && return
source "$OMARCHY_PATH/default/bash/rc"
EOF
ARCH_SEED="$T/seed_arch"; cat > "$ARCH_SEED" <<'EOF'
#
# ~/.bashrc
#
[[ $- != *i* ]] && return
alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
EOF

apply() { # apply <label> <family> <env> <seedfile|-> : fresh home with seed, apply files only
  local h="$T/home_$1"; mkdir -p "$h/.config"   # a real home always has ~/.config (chezmoi won't create the parent of a targeted subdirectory)
  [ "$4" != "-" ] && cp "$4" "$h/.bashrc"
  printf '[data]\n  family = "%s"\n  env = "%s"\n' "$2" "$3" > "$T/cfg_$1.toml"
  chezmoi --source "$SRC" --config "$T/cfg_$1.toml" --persistent-state "$T/st_$1.db" --cache "$T/cache" \
    --destination "$h" apply --include=files,dirs "$h/.bashrc" "$h/.config/shell" >"$T/apply_$1.log" 2>&1
}
# runbash <home> '<script>' : interactive bash, clean env, that home. TMUX=1 only keeps the fastfetch banner out
# of the output. (No comment may follow a line-continuation backslash: `\ # x` is not a continuation.)
runbash() {
  env -i HOME="$1" PATH="/usr/bin:/bin" TERM=xterm USER=tester LANG=C.UTF-8 XDG_RUNTIME_DIR="$1" TMUX=1 \
    MISE_DATA_DIR="$1/.mise" MISE_STATE_DIR="$1/.mise" MISE_CONFIG_DIR="$1/.mise" MISE_CACHE_DIR="$1/.mise" \
    bash -i -c "$2" 2>&1 | grep -v -e 'no job control' -e 'cannot set terminal process group' -e 'Inappropriate ioctl'; }

structure_checks() { # structure_checks <label> <seed|->
  local h="$T/home_$1" f="$T/home_$1/.bashrc"
  [ "$(grep -c 'dotfiles head' "$f")" = 0 ] && ok "[$1] no head block (ble.sh is loaded inside the tail block, after Omarchy's rc / bash-defaults)" || bad "[$1] a head block is present" "$(head -3 "$f")"
  [ "$(tail -1 "$f")" = "# <<< dotfiles (chezmoi) <<<" ] && ok "[$1] tail block is last" || bad "[$1] tail block position" "$(tail -3 "$f")"
  [ "$(grep -c '>>> dotfiles (chezmoi)' "$f")" = 1 ] && ok "[$1] exactly one managed block" || bad "[$1] block count"
  # ble.sh is sourced AFTER the rc it must not disturb, and attached last
  awk '/source "\$_ble" --noattach/{b=NR} /ble-attach/{a=NR} /default\/bash\/rc|bash-defaults/{if(!r)r=NR} END{exit !(b && a && r && r<b && b<a)}' "$f" && ok "[$1] order: defaults, then ble.sh --noattach, then ble-attach last" || bad "[$1] ble.sh load order" "$(grep -n -E 'noattach|ble-attach|default/bash/rc|bash-defaults' "$f")"
  if [ "$2" != "-" ]; then   # the original content must still be there, untouched and in order
    cp "$f" "$T/stripped_$1"
    sed '/^# >>> dotfiles (chezmoi) >>>/,/^# <<< dotfiles (chezmoi) <<</d' "$T/stripped_$1" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$T/orig_$1"
    diff <(sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$2") "$T/orig_$1" >/dev/null && ok "[$1] the original file content is preserved unchanged" || bad "[$1] original content altered" "$(diff "$2" "$T/orig_$1" | head -6)"
  fi
  bash -n "$f" && ok "[$1] result is valid bash" || bad "[$1] syntax"
  # idempotent: applying again changes nothing
  cp "$f" "$T/before_$1"
  chezmoi --source "$SRC" --config "$T/cfg_$1.toml" --persistent-state "$T/st_$1.db" --cache "$T/cache" --destination "$h" apply --include=files,dirs --force "$h/.bashrc" >/dev/null 2>&1
  cmp -s "$T/before_$1" "$f" && ok "[$1] re-apply is idempotent" || bad "[$1] re-apply changed the file" "$(diff "$T/before_$1" "$f" | head -6)"
  # user text outside the blocks survives a re-apply, and blocks are not duplicated
  { echo; echo "export MY_OWN_SETTING=kept"; } >> "$f"
  chezmoi --source "$SRC" --config "$T/cfg_$1.toml" --persistent-state "$T/st_$1.db" --cache "$T/cache" --destination "$h" apply --include=files,dirs --force "$h/.bashrc" >/dev/null 2>&1
  grep -q '^export MY_OWN_SETTING=kept$' "$f" && ! grep -q 'export MY_OWN_SETTING=kept.' "$f" && ! grep -q '[^[:space:]]export MY_OWN_SETTING' "$f" && [ "$(grep -c '>>> dotfiles (chezmoi)' "$f")" = 1 ] && ok "[$1] text you add outside the blocks survives, no duplicate blocks" || bad "[$1] user text / duplication"
}

echo "=== harness sanity"
mkdir -p "$T/sanity"
[ "$(runbash "$T/sanity" 'echo "$USER:$HOME:${EDITOR-unset}"')" = "tester:$T/sanity:unset" ] && ok "the test shell runs in a clean environment (own USER and HOME, no inherited EDITOR)" || bad "harness is NOT isolated" "$(runbash "$T/sanity" 'echo "$USER:$HOME:${EDITOR-unset}"')"

echo; echo "=== Omarchy (family=arch env=omarchy), seeded with Omarchy's own .bashrc"
if [ -d /usr/share/omarchy ]; then
  apply om arch omarchy "$OMARCHY_SEED"; [ -n "$(grep -v 'config file template has changed' "$T/apply_om.log")" ] && bad "[om] chezmoi apply output" "$(cat "$T/apply_om.log")"
  structure_checks om "$OMARCHY_SEED"
  out=$(runbash "$T/home_om" 'echo "ED=$EDITOR"; alias ls; type -t ga tdl hdl ssh zd; echo "OMARCHY_PATH=$OMARCHY_PATH"; echo END')
  echo "$out" | grep -q '^END$' && ok "[om] interactive bash starts and reaches the prompt" || bad "[om] interactive start" "$out"
  echo "$out" | grep -q '^ED=nvim$' && ok "[om] EDITOR=nvim overrides Omarchy's launcher" || bad "[om] EDITOR" "$out"
  echo "$out" | grep -q "alias ls='eza --group-directories-first --icons'" && ok "[om] ls is OUR alias (short), overriding Omarchy's long one" || bad "[om] ls alias" "$(echo "$out" | grep 'alias ls')"
  [ "$(echo "$out" | grep -c '^function$')" = 5 ] && ok "[om] ga, tdl, hdl, ssh and zd are all functions" || bad "[om] functions not all defined" "$out"
  echo "$out" | grep -q '^OMARCHY_PATH=/usr/share/omarchy$' && ok "[om] Omarchy's own environment is intact" || bad "[om] OMARCHY_PATH" "$out"
  errs=$(runbash "$T/home_om" 'true' | grep -v '^$' || true); [ -z "$errs" ] && ok "[om] no error output at startup" || bad "[om] startup errors" "$errs"
  # startup cost: our block vs Omarchy alone (median of 5, wall ms)
  ms() { local a=() i s e; for i in 1 2 3 4 5; do s=$EPOCHREALTIME; runbash "$1" 'exit' >/dev/null; e=$EPOCHREALTIME; a+=($(awk -v s=$s -v e=$e 'BEGIN{printf "%d",(e-s)*1000}')); done; printf '%s\n' "${a[@]}" | sort -n | sed -n 3p; }
  mkdir -p "$T/home_base"; cp "$OMARCHY_SEED" "$T/home_base/.bashrc"
  printf '  INFO  interactive startup (median of 5): Omarchy alone %s ms, with our block %s ms\n' "$(ms "$T/home_base")" "$(ms "$T/home_om")"
else echo "  skipped: /usr/share/omarchy not present on this machine"; fi

echo; echo "=== plain Arch (family=arch env=native), seeded with a stock Arch .bashrc"
apply pa arch native "$ARCH_SEED"; [ -n "$(grep -v 'config file template has changed' "$T/apply_pa.log")" ] && bad "[pa] chezmoi apply output" "$(cat "$T/apply_pa.log")"
structure_checks pa "$ARCH_SEED"
[ -f "$T/home_pa/.config/shell/bash-defaults" ] && [ -f "$T/home_pa/.config/shell/inputrc" ] && ok "[pa] bash-defaults and inputrc are deployed" || bad "[pa] bash-defaults/inputrc missing"
out=$(runbash "$T/home_pa" 'echo "HIST=$HISTSIZE"; echo "ED=$EDITOR"; type -t z zd ga; bind -P | grep -c menu-complete; echo "PC=$(declare -p PROMPT_COMMAND 2>&1)"; echo END')
echo "$out" | grep -q '^END$' && ok "[pa] interactive bash starts and reaches the prompt" || bad "[pa] interactive start" "$out"
echo "$out" | grep -q '^HIST=32768$' && ok "[pa] history settings applied" || bad "[pa] HISTSIZE" "$out"
echo "$out" | grep -q '^ED=nvim$' && ok "[pa] EDITOR=nvim" || bad "[pa] EDITOR" "$out"
command -v zoxide >/dev/null && { [ "$(echo "$out" | grep -c '^function$')" = 3 ] && ok "[pa] zoxide's z and our zd/ga are all functions" || bad "[pa] functions" "$out"; }
echo "$out" | grep -qE '^[1-9][0-9]*$' && ok "[pa] readline: Tab cycles (inputrc loaded)" || bad "[pa] inputrc" "$out"
command -v starship >/dev/null && { echo "$out" | grep -q '^PC=.*starship' && ok "[pa] starship prompt is initialised" || bad "[pa] starship" "$(echo "$out" | grep PC=)"; }
errs=$(runbash "$T/home_pa" 'true' | grep -v '^$' || true); [ -z "$errs" ] && ok "[pa] no error output at startup" || bad "[pa] startup errors" "$errs"

echo; echo "=== no ~/.bashrc yet (fresh plain-Arch/WSL user): the file is created from the blocks alone"
apply fr arch native -
[ -f "$T/home_fr/.bashrc" ] && ok "[fr] .bashrc created" || bad "[fr] no .bashrc"
structure_checks fr -
errs=$(runbash "$T/home_fr" 'echo END' | grep -v '^END$' || true); [ -z "$errs" ] && ok "[fr] starts cleanly" || bad "[fr] startup" "$errs"

echo; echo "=== other machine types must not get these files"
for spec in "ub debian native" "mac mac native" "ni - -"; do
  set -- $spec; label=$1; fam=$2; env=$3
  h="$T/home_$label"; mkdir -p "$h"
  if [ "$fam" = "-" ]; then printf '[data]\n  awsCli = false\n' > "$T/cfg_$label.toml"; else printf '[data]\n  family = "%s"\n  env = "%s"\n' "$fam" "$env" > "$T/cfg_$label.toml"; fi
  list=$(chezmoi --source "$SRC" --config "$T/cfg_$label.toml" --persistent-state "$T/st_$label.db" --cache "$T/cache" --destination "$h" managed 2>&1)
  case "$label" in ni) desc="no family data (not re-initialised yet)";; ub) desc="Ubuntu";; mac) desc="Mac";; esac
  echo "$list" | grep -qx -e '.bashrc' -e '.config/shell/bash-defaults' -e '.config/shell/inputrc' -e '.config/shell/bash-extras' && bad "[$label] $desc manages bash files" "$(echo "$list" | grep -E 'bashrc|bash-|inputrc')" || ok "[$label] $desc: .bashrc and bash-only files are not managed"
  echo "$list" | grep -qx '.zshrc' && ok "[$label] $desc: .zshrc is still managed" || bad "[$label] $desc lost .zshrc"
  echo "$list" | grep -qx '.config/shell/common.sh' && ok "[$label] $desc: common.sh is managed" || bad "[$label] $desc lacks common.sh"
done
list=$(chezmoi --source "$SRC" --config "$T/cfg_om.toml" --persistent-state "$T/st_om.db" --cache "$T/cache" --destination "$T/home_om" managed 2>&1)
echo "$list" | grep -qx '.zshrc' && bad "[om] Arch family still manages .zshrc" || ok "[om] Arch family: .zshrc is not managed"

echo; echo "=== migration: a ~/.bashrc written by the OLD template (head block at the top) is cleaned up"
mkdir -p "$T/home_mig"; printf '[data]\n  family = "arch"\n  env = "omarchy"\n' > "$T/cfg_mig.toml"
{ printf '%s\n' '# >>> dotfiles head (chezmoi) >>>' 'if [[ $- == *i* ]]; then source /usr/share/blesh/ble.sh --noattach; fi' '# <<< dotfiles head (chezmoi) <<<' ''; cat "$OMARCHY_SEED"; printf '\n%s\n' '# >>> dotfiles (chezmoi) >>>' 'old tail' '# <<< dotfiles (chezmoi) <<<'; } > "$T/home_mig/.bashrc"
chezmoi --source "$SRC" --config "$T/cfg_mig.toml" --persistent-state "$T/st_mig.db" --cache "$T/cache" --destination "$T/home_mig" apply --include=files,dirs --force "$T/home_mig/.bashrc" >/dev/null 2>&1
[ "$(grep -c 'dotfiles head' "$T/home_mig/.bashrc")" = 0 ] && [ "$(grep -c '>>> dotfiles (chezmoi)' "$T/home_mig/.bashrc")" = 1 ] && ! grep -q '^old tail$' "$T/home_mig/.bashrc" && ok "[migration] old head block removed, old tail block replaced, exactly one new block" || bad "[migration] old blocks not cleaned up" "$(grep -n 'dotfiles' "$T/home_mig/.bashrc")"
[ "$(head -1 "$T/home_mig/.bashrc")" = "$(head -1 "$OMARCHY_SEED")" ] && ok "[migration] the file now starts with Omarchy's own first line again" || bad "[migration] first line" "$(head -2 "$T/home_mig/.bashrc")"

echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL BASHRC CHECKS PASSED" || echo "SOME BASHRC CHECKS FAILED"
exit $fail
