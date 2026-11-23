#!/bin/bash
# Tests for the Neovim (LazyVim) config: chezmoi placement per machine type, then a real headless Neovim started from
# the committed lazy-lock.json in throwaway homes, with the assertions in .test/nvim-checks.lua.
#   .test/nvim.sh
# Needs the network the first time (it installs ~70 plugins into a cache that later runs reuse) plus nvim >= 0.12, git,
# curl, tree-sitter and a C compiler. The cache is NVIM_TEST_CACHE (default ~/.cache/dotfiles-nvim-test): safe to delete.
# Your real ~/.config/nvim and ~/.local/share/nvim are never used (it is proven at the end that they did not change).
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${NVIM_TEST_CACHE:-$HOME/.cache/dotfiles-nvim-test}"
command -v nvim >/dev/null 2>&1 || { echo "nvim not installed: skipped"; exit 0; }
T="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-nvim-test.XXXXXX")"
[ -n "$T" ] && [ -d "$T" ] || { echo "could not create temp dir"; exit 2; }
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/          /'; }
real_state() { { find ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim -maxdepth 3 -printf '%p %T@ %s\n' 2>/dev/null; } | cksum; }
REAL_BEFORE="$(real_state)"
mkdir -p "$CACHE/data"

# --- a throwaway home with the nvim config applied for a given machine: mkhome <label> <family> <env|-> [pre-hook]
mkhome() {
  local l=$1 f=$2 e=$3 h="$T/h_$1"; mkdir -p "$h/.config" "$h/.local/state"
  { echo '[data]'; [ "$f" != - ] && echo "  family = \"$f\""; [ "$e" != - ] && echo "  env = \"$e\""; } > "$T/cfg_$l.toml"
  [ -n "${4:-}" ] && "$4" "$h"
  chezmoi --source "$SRC" --config "$T/cfg_$l.toml" --persistent-state "$T/st_$l.db" --cache "$T/cache" --destination "$h" \
    apply --include=files,dirs,remove "$h/.config/nvim" > "$T/ap_$l.log" 2>&1
  [ -z "$(grep -v 'config file template has changed' "$T/ap_$l.log")" ] || bad "[$l] apply" "$(cat "$T/ap_$l.log")"; }
# Omarchy: ~/.config/nvim/lua/plugins/theme.lua is Omarchy's symlink to its current theme (here: the repo's committed copy)
omarchy_pre() {
  mkdir -p "$1/.local/state/omarchy/current/theme" "$1/.config/nvim/lua/plugins"
  cp "$SRC/dot_config/nvim/lua/plugins/theme.lua" "$1/.local/state/omarchy/current/theme/neovim.lua"
  ln -s ../../../../.local/state/omarchy/current/theme/neovim.lua "$1/.config/nvim/lua/plugins/theme.lua"; }
journal_pre() { mkdir -p "$1/Documents/personal/journal/scripts"; echo 'exit 0' > "$1/Documents/personal/journal/scripts/git-sync.sh"; }
# machine that still has the OLD kickstart config files (and files that must be left alone)
old_pre() {
  mkdir -p "$1/.config/nvim/lua/plugins"; for f in colorscheme copilot format lint lsp mini sql; do echo "return {} -- old" > "$1/.config/nvim/lua/plugins/$f.lua"; done
  echo "return {{ name = 'mine' }}" > "$1/.config/nvim/lua/obsidian_workspaces_local.lua"; echo "return {} -- keep" > "$1/.config/nvim/lua/plugins/my-own-plugin.lua"; }

echo "=== where the files go (chezmoi, per machine type)"
P=.config/nvim/lua
mkhome mac mac native;       H="$T/h_mac"
[ -f "$H/$P/plugins/theme.lua" ] && [ ! -L "$H/$P/plugins/theme.lua" ] && ok "[mac] theme.lua is installed as a regular file (the synced copy)" || bad "[mac] theme.lua"
[ ! -e "$H/$P/plugins/omarchy-theme-hotreload.lua" ] && [ ! -e "$H/$P/config/remote_clipboard.lua" ] && ok "[mac] the two Omarchy-only helpers are not installed" || bad "[mac] Omarchy helpers installed"
[ -f "$H/.config/nvim/lazyvim.json" ] && [ -f "$H/.config/nvim/lazy-lock.json" ] && [ -f "$H/.config/nvim/plugin/after/transparency.lua" ] && ok "[mac] lazyvim.json, lazy-lock.json and the transparency file are installed" || bad "[mac] core files"
mkhome wsl arch wsl;         H="$T/h_wsl"
[ -f "$H/$P/plugins/theme.lua" ] && [ ! -e "$H/$P/plugins/omarchy-theme-hotreload.lua" ] && ok "[wsl] theme.lua yes, Omarchy helpers no" || bad "[wsl] placement"
mkhome om arch omarchy omarchy_pre; H="$T/h_om"
[ -L "$H/$P/plugins/theme.lua" ] && [ "$(readlink "$H/$P/plugins/theme.lua")" = "../../../../.local/state/omarchy/current/theme/neovim.lua" ] && ok "[omarchy] Omarchy's theme.lua symlink is untouched by chezmoi (still a link to the same target)" || bad "[omarchy] symlink replaced" "$(ls -l "$H/$P/plugins/theme.lua")"
[ -f "$H/$P/plugins/omarchy-theme-hotreload.lua" ] && [ -f "$H/$P/config/remote_clipboard.lua" ] && ok "[omarchy] the live theme reload and the remote clipboard module are installed" || bad "[omarchy] helpers missing"
mkhome noinit - - omarchy_pre; H="$T/h_noinit"   # an Omarchy machine that has not re-run `chezmoi init`: no env data at all
[ -L "$H/$P/plugins/theme.lua" ] && ok "[not yet re-initialised] Omarchy's symlink survives too (fail-safe: the file is only installed where env is explicitly native or wsl)" || bad "[no env data] symlink was replaced" "$(ls -l "$H/$P/plugins/theme.lua")"
mkhome noinit2 - -;          H="$T/h_noinit2"
[ ! -e "$H/$P/plugins/theme.lua" ] && ok "[not yet re-initialised, no symlink] theme.lua is not written either (no guessing)" || bad "[no env data] theme.lua installed without knowing the machine"
mkhome old arch native old_pre; H="$T/h_old"
gone=1; for f in colorscheme copilot format lint lsp mini sql; do [ -e "$H/$P/plugins/$f.lua" ] && gone=0; done
[ $gone = 1 ] && ok "old kickstart plugin files are removed (colorscheme, copilot, format, lint, lsp, mini, sql)" || bad "old plugin files remain" "$(ls "$H/$P/plugins")"
[ -f "$H/$P/obsidian_workspaces_local.lua" ] && [ -f "$H/$P/plugins/my-own-plugin.lua" ] && ok "your per-machine obsidian_workspaces_local.lua and a plugin file of your own are left alone" || bad "a user file was removed"
mkhome oldom arch omarchy omarchy_pre; echo "return {} -- old" > "$T/h_oldom/$P/plugins/lsp.lua"
chezmoi --source "$SRC" --config "$T/cfg_oldom.toml" --persistent-state "$T/st_oldom.db" --cache "$T/cache" --destination "$T/h_oldom" apply --include=files,dirs,remove "$T/h_oldom/.config/nvim" >/dev/null 2>&1
[ ! -e "$T/h_oldom/$P/plugins/lsp.lua" ] && [ -L "$T/h_oldom/$P/plugins/theme.lua" ] && ok "[omarchy] a leftover old file is removed and the theme symlink is still there afterwards" || bad "[omarchy] remove/symlink interplay"
# the Omarchy files we copied must still be what Omarchy ships (so an Omarchy update to them is noticed by this test)
if [ -d /usr/share/omarchy ] || [ -d /etc/skel/.config/nvim ]; then
  K=/etc/skel/.config/nvim; if [ -d "$K" ]; then d=0
    for f in lua/plugins/all-themes.lua lua/plugins/disable-news-alert.lua lua/plugins/lualine-transparent.lua lua/plugins/snacks-animated-scrolling-off.lua lua/plugins/omarchy-theme-hotreload.lua lua/config/remote_clipboard.lua plugin/after/transparency.lua; do
      cmp -s "$K/$f" "$SRC/dot_config/nvim/$f" || { d=1; echo "          differs from Omarchy's skeleton: $f"; }; done
    [ $d = 0 ] && ok "the 7 Omarchy files in the repo are identical to Omarchy's skeleton in /etc/skel (a difference means Omarchy changed them: review it)" || { printf '  NOTE  an Omarchy file changed upstream; review the difference and update the repo copy\n'; }
  fi
fi

echo; echo "=== plugin install from the committed lock file (cache: $CACHE)"
nvrun() { # nvrun <home> <extra env assignments...> -- <nvim args...>
  local h=$1; shift; local envs=(); while [ "$1" != -- ]; do envs+=("$1"); shift; done; shift
  env -i HOME="$h" PATH=/usr/bin:/bin TERM=xterm-256color LANG=C.UTF-8 XDG_DATA_HOME="$CACHE/data" "${envs[@]}" timeout 900 nvim --headless "$@" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }
LOCKSUM="$(cksum < "$SRC/dot_config/nvim/lazy-lock.json")"
if [ ! -d "$CACHE/data/nvim/lazy/LazyVim" ] || [ "$(cat "$CACHE/locksum" 2>/dev/null)" != "$LOCKSUM" ]; then
  echo "  (installing/restoring plugins from the lock file: this takes a few minutes)"
  mkdir -p "$T/h_mac/Documents/personal/second-brain"   # a vault, so obsidian.nvim is enabled, installed and checked against the lock too
  out=$(nvrun "$T/h_mac" -- "+Lazy! restore" "+qa")
  echo "$out" | grep -qiE 'failed|error' && bad "Lazy restore reported problems" "$(echo "$out" | grep -iE 'failed|error' | head -5)"
  nvrun "$T/h_mac" -- '+lua local ok,t=pcall(function() return require("nvim-treesitter").install({"lua","markdown","markdown_inline","vim","vimdoc","regex","bash","python"}) end); if ok and t then t:wait(900000) end' "+qa" >/dev/null
  nvrun "$T/h_mac" -- '+lua require("lazy").load({plugins={"mason.nvim"}}); local r=require("mason-registry"); local done=false; r.refresh(function() local p=r.get_package("stylua"); if not p:is_installed() then p:install():once("closed", function() done=true end) else done=true end end); vim.wait(300000, function() return done end)' "+qa" >/dev/null
  echo "$LOCKSUM" > "$CACHE/locksum"
fi
[ -d "$CACHE/data/nvim/lazy/LazyVim" ] && ok "LazyVim and its plugins are installed ($(ls "$CACHE/data/nvim/lazy" | wc -l) plugin directories)" || { bad "plugins did not install"; echo "passed=$pass failed=$fail"; exit 1; }
cmp -s "$T/h_mac/.config/nvim/lazy-lock.json" "$SRC/dot_config/nvim/lazy-lock.json" && ok "installing from the lock file did not change it (the lock is complete and consistent)" || bad "lazy-lock.json changed while installing from it" "$(diff "$T/h_mac/.config/nvim/lazy-lock.json" "$SRC/dot_config/nvim/lazy-lock.json" | head -6)"

runchecks() { # runchecks <label> <home> <mode> [extra env...]
  local l=$1 h=$2 m=$3; shift 3; mkdir -p "$T/scratch_$l"
  echo; echo "=== Neovim $l"
  out=$(nvrun "$h" CHK_MODE="$m" CHK_TMP="$T/scratch_$l" CHK_LOCK="$SRC/dot_config/nvim/lazy-lock.json" TMUX=/tmp/fake,1,0 "$@" -- "+luafile $SRC/.test/nvim-checks.lua")
  echo "$out" | grep -E '^(PASS|FAIL) ' | while IFS= read -r line; do
    case "$line" in PASS\ *) printf '  PASS  %s\n' "${line#PASS }";; FAIL\ *) printf '  FAIL  %s\n' "${line#FAIL }";; esac; done
  p=$(echo "$out" | grep -c '^PASS '); f=$(echo "$out" | grep -c '^FAIL '); pass=$((pass+p)); fail=$((fail+f))
  [ "$p" -gt 40 ] || bad "[$l] the check script produced only $p passing checks (it probably did not run to the end)" "$(echo "$out" | grep -vE '^(PASS|FAIL) ' | tail -6)"; }
mkhome native arch native;   runchecks "on a Mac / plain machine (env=native)" "$T/h_native" native
mkhome jr arch native journal_pre; runchecks "on a machine that has the journal" "$T/h_jr" journal
vault_pre() { mkdir -p "$1/Documents/personal/second-brain"; }
mkhome vt arch native vault_pre; runchecks "on a machine that has an Obsidian vault" "$T/h_vt" vault
mkhome om2 arch omarchy omarchy_pre; runchecks "on Omarchy (theme.lua is Omarchy's symlink)" "$T/h_om2" omarchy

echo; echo "=== cleanliness"
lockbad=0; for h in native jr vt om2; do cmp -s "$T/h_$h/.config/nvim/lazy-lock.json" "$SRC/dot_config/nvim/lazy-lock.json" || { lockbad=1; bad "[$h] lazy-lock.json was modified by running Neovim"; }; done
[ $lockbad = 0 ] && ok "running Neovim did not rewrite lazy-lock.json in any scenario"
[ "$(real_state)" = "$REAL_BEFORE" ] && ok "your real ~/.config/nvim, ~/.local/share/nvim and ~/.local/state/nvim did not change during this test" || bad "a real nvim directory changed during the test"
n=$(pgrep -fa "nvim --headless" | grep -c "$T"); [ "$n" = 0 ] && ok "no test Neovim process is left running" || bad "$n test Neovim processes still running"

echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL NVIM CHECKS PASSED" || echo "SOME NVIM CHECKS FAILED"
exit $fail
