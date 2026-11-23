#!/bin/bash
# Tests for the generated starship tiers (starship_palettes() in scripts/sync-omarchy-theme.py): for EVERY Omarchy theme
# installed on this machine and each of the three palettes (omarchy, omarchy-dark, omarchy-light) the colours must be
# readable, the pills must be an ordered ladder with a plainly visible step between every neighbour (OKLab lightness), and the real starship must render the result with no warnings.
# Also the generator's behaviour: idempotent, skips what it cannot derive, refuses bad colours without writing.
# Everything happens in throwaway directories; Omarchy's themes are only READ.
#   .test/starship-tiers.sh
set -uo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$SRC/scripts/sync-omarchy-theme.py"
command -v python3 >/dev/null 2>&1 || { echo "python3 not installed: skipped"; exit 0; }
T="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tiers-test.XXXXXX")"
[ -n "$T" ] && [ -d "$T" ] || { echo "could not create temp dir"; exit 2; }
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/          /'; }

THEMES=$(ls /usr/share/omarchy/themes/*/colors.toml 2>/dev/null)
[ -n "$THEMES" ] || { echo "Omarchy's themes are not on this machine: skipped"; exit 0; }

echo "=== every theme, every palette: readability and ladder (pure computation)"
res=$(python3 -I - "$GEN" $THEMES <<'PY'
import importlib.util, sys, tomllib, os
spec = importlib.util.spec_from_file_location("gen", sys.argv[1]); g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
n = 0; worst = {}
def note(key, val, label):
    if key not in worst or val < worst[key][0]: worst[key] = (val, label)
problems = []
for f in sys.argv[2:]:
    name = os.path.basename(os.path.dirname(f))
    c = g.read_colors_toml(os.path.dirname(f))
    if c is None: problems.append(f"{name}: colors.toml not complete enough"); continue
    pals = g.starship_palettes(c)
    if set(pals) != {"omarchy", "omarchy-dark", "omarchy-light"}: problems.append(f"{name}: palettes {sorted(pals)}"); continue
    if pals["omarchy"] != pals[f"omarchy-{c['mode']}"]: problems.append(f"{name}: omarchy != its own mode")
    other = "light" if c["mode"] == "dark" else "dark"
    bases = {"omarchy": c["background"], f"omarchy-{c['mode']}": c["background"], f"omarchy-{other}": g._synth_base(c["accent"], other)}
    for pn, p in pals.items():
        n += 1; L = f"{name}/{pn}"
        if not all(g.HEX.match(v) for v in p.values()) or len(p) != 12: problems.append(f"{L}: bad values"); continue
        # text on every pill that carries it
        for k, (a, b, want) in {"os text": (p["pill_os_fg"], p["pill_os_bg"], 4.5), "directory text": (p["pill_dir_fg"], p["pill_dir_bg"], 4.5),
                                "git text": (p["pill_text"], p["pill_git_bg"], 4.5), "language text": (p["pill_text"], p["pill_lang_bg"], 4.5),
                                "duration text": (p["pill_text"], p["pill_dur_bg"], 4.5), "git change marker": (p["pill_change"], p["pill_git_bg"], 3.4)}.items():
            r = g.contrast(a, b); note(k, r, L)
            if r < want - 1e-9: problems.append(f"{L}: {k} contrast {r:.2f} < {want}")
        # THE LADDER, in perceptual lightness: every pill must be plainly different from the one next to it, and the last
        # one from the terminal background (a pill that melts into its neighbour or the background is invisible)
        light = g.lightness
        seq = [("background", bases[pn]), ("duration", p["pill_dur_bg"]), ("language", p["pill_lang_bg"]), ("git", p["pill_git_bg"]), ("directory", p["pill_dir_bg"])]
        for (n1, c1), (n2, c2) in zip(seq, seq[1:]):
            d = abs(light(c1) - light(c2)); note(f"step {n1}->{n2}", d, L)
            if d < 0.07 - 1e-9: problems.append(f"{L}: {n1} and {n2} differ by only {d:.3f} lightness (need 0.07)")
        mono = [light(c) for _, c in seq]
        if not (all(x < y for x, y in zip(mono, mono[1:])) or all(x > y for x, y in zip(mono, mono[1:]))):
            problems.append(f"{L}: the ladder background -> duration -> language -> git -> directory is not monotonic")
        d = abs(light(p["pill_os_bg"]) - light(p["pill_dir_bg"])); note("step os->directory", d, L)
        if d < 0.07 - 1e-9: problems.append(f"{L}: the OS and directory pills differ by only {d:.3f} lightness (need 0.07)")
print(f"checked {n} palettes")
for k, (v, L) in sorted(worst.items()): print(f"worst {k}: {v:.3f} ({L})")
for p in problems: print("PROBLEM", p)
PY
)
printf '%s\n' "$res" | grep -v '^PROBLEM' | sed 's/^/          /'
printf '%s\n' "$res" | grep -q '^checked 69 palettes' && ok "69 palettes computed (23 themes x 3)" || bad "palette count" "$(printf '%s\n' "$res" | head -3)"
probs=$(printf '%s\n' "$res" | grep '^PROBLEM' || true)
[ -z "$probs" ] && ok "text is readable (4.5:1) on every pill, and every pill differs from its neighbours and from the background by a visible step, in all of them" || bad "readability/ladder problems" "$probs"

echo; echo "=== the real starship renders every theme (all three palettes, no warnings)"
if command -v starship >/dev/null 2>&1 && command -v chezmoi >/dev/null 2>&1; then
  mkdir -p "$T/p" "$T/home"; printf '[data]\n  family = "mac"\n  env = "native"\n' > "$T/cfg.toml"
  S="$T/src"; mkdir -p "$S/.chezmoitemplates" "$S/dot_config"; : > "$S/.chezmoi.toml.tmpl"
  cp "$SRC/.chezmoitemplates/starship-tiered.toml" "$S/.chezmoitemplates/"; cp "$SRC"/dot_config/starship*.tmpl "$S/dot_config/"
  badthemes=""; n=0
  for f in $THEMES; do
    t=$(basename "$(dirname "$f")"); n=$((n+1))
    # a theme dir shaped like Omarchy's runtime one: ghostty.conf is made up (the generator needs one, starship does not)
    d="$T/th/$t/theme"; mkdir -p "$d"; cp "$f" "$d/colors.toml"
    python3 -I - "$f" "$d/ghostty.conf" <<'PY'
import tomllib,sys
c=tomllib.load(open(sys.argv[1],'rb')); names="black red green yellow blue magenta cyan white".split()
out=[f"background = {c['background']}",f"foreground = {c['foreground']}"]
for i in range(16):
    k=names[i%8]; out.append(f"palette = {i}={c.get(k, c['foreground'])}")
open(sys.argv[2],'w').write("\n".join(out)+"\n")
PY
    python3 -I "$GEN" --theme-dir "$d" --repo "$S" >/dev/null 2>"$T/gen.err" || { badthemes="$badthemes $t(generator)"; continue; }
    rm -rf "$T/home/.config"; mkdir -p "$T/home/.config"
    chezmoi --source "$S" --config "$T/cfg.toml" --persistent-state "$T/st.db" --cache "$T/cache" --destination "$T/home" apply --include=files --force "$T/home/.config/starship.toml" "$T/home/.config/starship-dark.toml" "$T/home/.config/starship-light.toml" >"$T/ap.err" 2>&1 || { badthemes="$badthemes $t(apply)"; continue; }
    for v in starship starship-dark starship-light; do
      w=$(env -i HOME="$T/home" PATH=/usr/bin:/bin STARSHIP_CONFIG="$T/home/.config/$v.toml" starship print-config 2>&1 >/dev/null)
      o=$(env -i HOME="$T/home" PATH=/usr/bin:/bin TERM=xterm-256color STARSHIP_CONFIG="$T/home/.config/$v.toml" starship prompt --path "$T/p" --terminal-width 100 --status 0 2>&1)
      [ -z "$w" ] && case "$o" in *❯*) ;; *) w="no prompt char";; esac
      [ -n "$w" ] && badthemes="$badthemes $t/$v"
    done
  done
  [ -z "$badthemes" ] && ok "$n themes: generated, rendered by chezmoi, parsed and drawn by starship with all three files" || bad "themes that failed:" "$badthemes"
else echo "  (starship or chezmoi missing: rendering skipped)"; fi

echo; echo "=== the generator itself"
mkrepo() { mkdir -p "$1"; : > "$1/.chezmoi.toml.tmpl"; }
mktheme() { # mktheme <dir> [colors.toml extra lines]: a minimal theme dir: ghostty.conf + colors.toml
  local d=$1; mkdir -p "$d"
  { echo "background = #0a0a14"; echo "foreground = #d0d0ff"; for i in $(seq 0 15); do echo "palette = $i=#30303$((i%10))"; done; } > "$d/ghostty.conf"
  printf 'mode = "dark"\naccent = "#82aaff"\nbackground = "#0a0a14"\nforeground = "#d0d0ff"\nred = "#ff4d6d"\ncyan = "#89ddff"\nmagenta = "#c792ea"\n%s\n' "${2:-}" > "$d/colors.toml"
}
OUT=.chezmoitemplates/starship-palettes.toml
mkrepo "$T/r1"; mktheme "$T/c1/theme"
python3 -I "$GEN" --theme-dir "$T/c1/theme" --repo "$T/r1" 2>"$T/e1"; [ -s "$T/r1/$OUT" ] && ok "writes $OUT (creating the directory)" || bad "no output" "$(cat "$T/e1")"
python3 -I - "$T/r1/$OUT" <<'PY' && ok "the output is valid TOML with the three palettes" || bad "output content"
import tomllib,sys
d=tomllib.load(open(sys.argv[1],'rb'))['palettes']; assert set(d)=={'omarchy','omarchy-dark','omarchy-light'}, set(d)
assert all(len(p)==12 for p in d.values())
PY
head -1 "$T/r1/$OUT" | grep -q '^# GENERATED by scripts/sync-omarchy-theme.py' && ok "it carries the GENERATED header" || bad "no header"
python3 -I "$GEN" --theme-dir "$T/c1/theme" --repo "$T/r1" --check 2>/dev/null && ok "--check: a second run changes nothing (idempotent)" || bad "not idempotent"
python3 -I "$GEN" --theme-dir "$T/c1/theme" --repo "$T/r1" 2>&1 | grep -q "unchanged .*starship-palettes" && ok "a second run reports unchanged" || bad "second run status"

mkrepo "$T/r2"; mktheme "$T/c2/theme"; sed -i '/^cyan/d' "$T/c2/theme/colors.toml"
python3 -I "$GEN" --theme-dir "$T/c2/theme" --repo "$T/r2" 2>"$T/e2"; rc=$?
[ $rc -eq 0 ] && [ ! -e "$T/r2/$OUT" ] && [ -f "$T/r2/dot_config/otty/themes/omarchy.ottytheme" ] && grep -q "skipped.*starship-palettes" "$T/e2" && ok "a colors.toml without 'cyan': this output is skipped, the others are still written" || bad "incomplete colors.toml" "rc=$rc $(cat "$T/e2")"

mkrepo "$T/r3"; mktheme "$T/c3/theme"; echo "keep" > "$T/r3/marker"; sed -i 's/^accent.*/accent = "blue"/' "$T/c3/theme/colors.toml"
python3 -I "$GEN" --theme-dir "$T/c3/theme" --repo "$T/r3" 2>"$T/e3"; rc=$?
[ $rc -eq 2 ] && [ ! -e "$T/r3/$OUT" ] && [ ! -e "$T/r3/dot_config" ] && grep -q "accent is not #rrggbb" "$T/e3" && ok "a bad accent colour: exit 2, nothing written anywhere" || bad "bad accent not refused" "rc=$rc $(cat "$T/e3")"

mkrepo "$T/r4"; mktheme "$T/c4/theme"; sed -i 's/^mode.*/mode = "light"/; s/^background = "#0a0a14"/background = "#faf4ed"/; s/^foreground = "#d0d0ff"/foreground = "#575279"/' "$T/c4/theme/colors.toml"
python3 -I "$GEN" --theme-dir "$T/c4/theme" --repo "$T/r4" 2>/dev/null
python3 -I - "$T/r4/$OUT" "$T/r1/$OUT" <<'PY' && ok "a light theme: 'omarchy' is the light palette; a dark theme: it is the dark one" || bad "mode mapping"
import tomllib,sys
l=tomllib.load(open(sys.argv[1],'rb'))['palettes']; d=tomllib.load(open(sys.argv[2],'rb'))['palettes']
assert l['omarchy']==l['omarchy-light'] and l['omarchy']!=l['omarchy-dark']
assert d['omarchy']==d['omarchy-dark'] and d['omarchy']!=d['omarchy-light']
PY

# degenerate: accent identical to the background must not crash or produce unreadable text
python3 -I - "$GEN" <<'PY' && ok "degenerate themes (accent = background, pure black or white) still give readable palettes" || bad "degenerate themes"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("gen", sys.argv[1]); g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
for bg, fg, acc, mode in (("#000000","#ffffff","#000000","dark"),("#ffffff","#000000","#ffffff","light"),("#808080","#808080","#808080","dark"),("#101010","#f0f0f0","#f0f0f0","dark")):
    c = dict(background=bg, foreground=fg, accent=acc, red="#ff0000", cyan="#00ffff", magenta="#ff00ff", mode=mode)
    pals = g.starship_palettes(c)
    for n, p in pals.items():
        assert all(g.HEX.match(v) for v in p.values()), (bg, acc, n)
        assert g.contrast(p["pill_dir_fg"], p["pill_dir_bg"]) >= 4.4, (bg, acc, n, "dir")
        assert g.contrast(p["pill_os_fg"], p["pill_os_bg"]) >= 4.4, (bg, acc, n, "os")
PY

echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ] && echo "ALL STARSHIP TIER CHECKS PASSED" || echo "SOME STARSHIP TIER CHECKS FAILED"
exit $fail
