#!/bin/bash
# Tests for the fastfetch banner: dot_config/shell/banner.sh (when and how it prints), the real
# dot_config/fastfetch/banner.jsonc layout, and the Omarchy placement rule (no config.jsonc on Omarchy, so its
# About window keeps its own layout). Interactive shells run in a pseudo-terminal with stdin closed.
#   .test/banner.sh
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
command -v script >/dev/null 2>&1 || { echo "script(1) not available: skipped"; exit 0; }
T="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-banner-test.XXXXXX")"
[ -n "$T" ] && [ -d "$T" ] || { echo "could not create temp dir"; exit 2; }
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/          /'; }

# ---- Part A: the function, against a stand-in fastfetch that records its arguments ---------------------------
echo "=== A. banner.sh behaviour (stand-in fastfetch, real interactive shells)"
H="$T/home"; mkdir -p "$H/.config/fastfetch" "$T/stubs" "$T/nostub"
echo '{}' > "$H/.config/fastfetch/banner.jsonc"; echo '{}' > "$H/.config/fastfetch/compact.jsonc"
cat > "$T/stubs/fastfetch" <<EOF
#!/bin/sh
echo "fastfetch \$*" >> "$T/ff.log"
case "\$*" in *compact.jsonc*) printf 'user@host\nArch Linux\nup 3d 2h\nmem 40%%\n' ;; *) echo "FULL BANNER" ;; esac
EOF
chmod +x "$T/stubs/fastfetch"
runshell() { # runshell <shell> <extra env assignments...> -- : load banner.sh interactively in that shell
  local sh=$1; shift
  : > "$T/ff.log"; printf '. "%s/dot_config/shell/banner.sh"; echo "FUNC:$(type _dotfiles_banner >/dev/null 2>&1 && echo left || echo gone)"; echo DONE\n' "$SRC" > "$T/snip"
  local flags; case $sh in bash) flags="--norc --noprofile";; zsh) flags="-f";; esac
  timeout 30 script -qec "env -i HOME=$H PATH=$T/stubs:/usr/bin:/bin TERM=xterm LANG=C.UTF-8 $* $sh $flags -i -c '. $T/snip'" /dev/null </dev/null 2>&1 | tr -d '\r'
}
for sh in bash zsh; do
  command -v $sh >/dev/null 2>&1 || { echo "  ($sh not installed: skipped)"; continue; }
  out=$(runshell $sh); calls=$(cat "$T/ff.log")
  [ "$calls" = "fastfetch -c $H/.config/fastfetch/banner.jsonc" ] && echo "$out" | grep -q 'FULL BANNER' && ok "[$sh] local terminal: full banner via -c banner.jsonc" || bad "[$sh] local" "calls=[$calls] out=[$out]"
  echo "$out" | grep -q '^FUNC:gone$' && ok "[$sh] the helper function is removed after use (nothing leaks into the shell)" || bad "[$sh] function left behind" "$out"
  out=$(runshell $sh TMUX=1); [ -z "$(cat "$T/ff.log")" ] && ! echo "$out" | grep -q 'FULL BANNER' && ok "[$sh] inside tmux: nothing" || bad "[$sh] tmux" "$(cat "$T/ff.log")"
  out=$(runshell $sh HERDR_ENV=1); [ -z "$(cat "$T/ff.log")" ] && ! echo "$out" | grep -q 'FULL BANNER' && ok "[$sh] inside herdr: nothing" || bad "[$sh] herdr" "$(cat "$T/ff.log")"
  out=$(runshell $sh SSH_CONNECTION="1.2.3.4_5_6.7.8.9_22"); calls=$(cat "$T/ff.log")
  [ "$calls" = "fastfetch -c $H/.config/fastfetch/compact.jsonc --pipe false" ] && ok "[$sh] over SSH: the compact layout" || bad "[$sh] ssh call" "calls=[$calls]"
  plain=$(echo "$out" | sed 's/\x1b\[[0-9;]*m//g')   # the separators are drawn in grey (ANSI 90)
  echo "$plain" | grep -qF 'user@host  ·  Arch Linux  ·  up 3d 2h  ·  mem 40%' && ok "[$sh] over SSH: the lines are joined into ONE line with · separators" || bad "[$sh] ssh joining" "$out"
  [ "$(echo "$out" | grep -c 'user@host')" = 1 ] && ok "[$sh] over SSH: exactly one output line" || bad "[$sh] ssh line count" "$out"
  mv "$H/.config/fastfetch/banner.jsonc" "$T/banner.bak"; out=$(runshell $sh); calls=$(sed 's/[[:space:]]*$//' "$T/ff.log"); mv "$T/banner.bak" "$H/.config/fastfetch/banner.jsonc"
  [ "$calls" = "fastfetch" ] && ok "[$sh] layout file missing: falls back to plain fastfetch" || bad "[$sh] fallback" "calls=[$calls]"
  # no fastfetch at all: PATH without the stub dir (and /usr/bin here has the real one, so hide it with a PATH that only has the shell)
  : > "$T/ff.log"; printf '. "%s/dot_config/shell/banner.sh"; echo "RC=$?"\n' "$SRC" > "$T/snip2"
  case $sh in bash) fl="--norc --noprofile";; zsh) fl="-f";; esac
  nb="$T/nofastfetch"; mkdir -p "$nb"; for x in awk sh bash zsh env; do p=$(command -v $x) && ln -sf "$p" "$nb/$x"; done
  out=$(timeout 30 script -qec "env -i HOME=$H PATH=$nb TERM=xterm $sh $fl -i -c '. $T/snip2'" /dev/null </dev/null 2>&1 | tr -d '\r')
  [ "$out" = "RC=0" ] && ok "[$sh] no fastfetch installed: silent, returns 0" || bad "[$sh] missing binary" "$out"
done
# non-interactive shells must never print it
: > "$T/ff.log"; env -i HOME="$H" PATH="$T/stubs:/usr/bin:/bin" bash -c ". '$SRC/dot_config/shell/banner.sh'"; [ -z "$(cat "$T/ff.log")" ] && ok "[bash] non-interactive shell: nothing" || bad "[bash] non-interactive" "$(cat "$T/ff.log")"

# ---- Part B: the real layout, installed by chezmoi, rendered by the real fastfetch ---------------------------
echo; echo "=== B. the real banner.jsonc through chezmoi and fastfetch"
install() { # install <label> <family> <env> : apply the fastfetch dir into a throwaway home
  local h="$T/hm_$1"; mkdir -p "$h/.config"
  printf '[data]\n  family = "%s"\n  env = "%s"\n' "$2" "$3" > "$T/cfg_$1.toml"
  chezmoi --source "$SRC" --config "$T/cfg_$1.toml" --persistent-state "$T/st_$1.db" --cache "$T/cache" --destination "$h" \
    apply --include=files,dirs,symlinks "$h/.config/fastfetch" > "$T/ap_$1.log" 2>&1
  [ -z "$(grep -v 'config file template has changed' "$T/ap_$1.log")" ] || bad "[$1] apply output" "$(cat "$T/ap_$1.log")"; }
install om arch omarchy; install ub debian native; install pa arch native
for l in om ub pa; do d="$T/hm_$l/.config/fastfetch"
  [ -f "$d/banner.jsonc" ] && [ -f "$d/compact.jsonc" ] && [ -f "$d/logo-keys.txt" ] && ok "[$l] banner.jsonc, compact.jsonc and logo-keys.txt are installed" || bad "[$l] files missing" "$(ls "$d")"; done
if command -v fastfetch >/dev/null 2>&1; then
  d="$T/hm_ub/.config/fastfetch"
  # Omarchy puts omarchy-version / omarchy-theme-current in /usr/bin itself, so "commands unavailable" needs a PATH
  # that holds only fastfetch and sh.
  mkdir -p "$T/ffonly"; ln -sf "$(command -v fastfetch)" "$T/ffonly/fastfetch"; ln -sf "$(command -v sh)" "$T/ffonly/sh"
  CLEAN=(env -i HOME="$T/hm_ub" PATH="$T/ffonly" TERM=xterm LANG=C.UTF-8)
  out=$("${CLEAN[@]}" fastfetch -c "$d/banner.jsonc" --pipe 2>&1); rc=$?
  [ $rc -eq 0 ] && ok "fastfetch renders the real banner.jsonc (exit 0)" || bad "render exit $rc" "$out"
  for row in 'kernel' 'pkgs' 'host' 'memory' 'disk' 'uptime' 'shell'; do echo "$out" | grep -q " $row " && ok "row present: $row" || bad "row missing: $row" "$(echo "$out" | head -12)"; done
  echo "$out" | grep -q '╭─' && echo "$out" | grep -q '╰─' && ok "the tree frame (top and bottom) is drawn" || bad "frame" "$out"
  echo "$out" | grep -qE ' omarchy |  theme ' && bad "Omarchy-only rows showed up with Omarchy commands unavailable" "$out" || ok "Omarchy-only rows are hidden where the omarchy commands do not exist"
  echo "$out" | grep -qE ' wsl ' && bad "wsl row showed up outside WSL" || ok "the wsl row is hidden outside WSL"
  if command -v omarchy-version >/dev/null 2>&1 && command -v omarchy-theme-current >/dev/null 2>&1; then
    out=$(HOME="$T/hm_ub" fastfetch -c "$d/banner.jsonc" --pipe 2>&1)
    echo "$out" | grep -q ' omarchy ' && echo "$out" | grep -q ' theme ' && ok "with the omarchy commands available, the omarchy and theme rows appear" || bad "omarchy rows missing on Omarchy" "$out"
  fi
  out=$("${CLEAN[@]}" fastfetch -c "$d/compact.jsonc" --pipe false 2>&1); [ -n "$out" ] && ok "compact.jsonc still renders" || bad "compact render"
else echo "  (fastfetch not installed: render checks skipped)"; fi

# ---- Part C: the Omarchy About-window rule -------------------------------------------------------------------
echo; echo "=== C. Omarchy's About window must keep its own layout"
[ ! -e "$T/hm_om/.config/fastfetch/config.jsonc" ] && [ ! -L "$T/hm_om/.config/fastfetch/config.jsonc" ] && ok "Omarchy: NO config.jsonc is installed (fastfetch would pick it up before /etc/fastfetch)" || bad "Omarchy has a config.jsonc"
for l in ub pa; do c="$T/hm_$l/.config/fastfetch/config.jsonc"
  [ -L "$c" ] && [ "$(readlink "$c")" = "banner.jsonc" ] && [ -f "$c" ] && ok "[$l] config.jsonc is a symlink to banner.jsonc (plain fastfetch matches the banner)" || bad "[$l] config.jsonc" "$(ls -la "$T/hm_$l/.config/fastfetch")"; done

echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL BANNER CHECKS PASSED" || echo "SOME BANNER CHECKS FAILED"
exit $fail
