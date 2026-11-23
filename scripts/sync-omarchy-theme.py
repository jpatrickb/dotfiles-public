#!/usr/bin/env python3
"""Regenerate this repo's terminal theme files from Omarchy's CURRENT theme.

Omarchy is the source of truth for colours. When you switch theme on Omarchy it writes the terminal palette it
uses into ~/.local/state/omarchy/current/theme/ghostty.conf. This script reads that file and writes the two files
the other machines need into the chezmoi source tree:

  dot_config/otty/themes/omarchy.ottytheme    Otty (Mac, and Windows/WSL): theme = omarchy
  dot_config/noctty/omarchy-theme.conf        Noctty, the Windows fallback terminal (Ghostty config format)
  dot_config/nvim/lua/plugins/theme.lua       Neovim: Omarchy's own generated LazyVim theme spec, copied unchanged
                                              (on Omarchy itself ~/.config/nvim/lua/plugins/theme.lua is Omarchy's
                                              symlink to that file, so chezmoi ignores this path there)
  .chezmoitemplates/starship-palettes.toml    the tiered starship prompt colours (three palettes: omarchy, omarchy-dark,
                                              omarchy-light), derived from colors.toml: see starship_palettes() below

It is run by the Omarchy theme-set hook (dot_config/omarchy/hooks/theme-set.d/20-dotfiles-theme-sync) and can be run
by hand. It only ever writes files in the repo working tree: it never commits and never pushes. Review the diff
and commit when you want the other machines to pick the theme up (`chezmoi git -- pull` + `chezmoi apply` there).

Strict on purpose: the input must contain a background, a foreground and all 16 palette entries as #rrggbb, or
nothing is written and the existing files stay exactly as they were. The same goes for neovim.lua if it is present
(it must look like a LazyVim theme spec); if it is absent only that one output is skipped. Outputs are only rewritten when their content
changes, so a theme switch that changes nothing leaves the repo clean.

Usage:
  sync-omarchy-theme.py [--theme-dir DIR] [--repo DIR] [--check]
    --theme-dir  Omarchy's current theme directory (default ~/.local/state/omarchy/current/theme)
    --repo       the chezmoi source directory (default: `chezmoi source-path`, else ~/.local/share/chezmoi)
    --check      write nothing; exit 1 if any output would change (for tests)
Exit status: 0 ok, 1 --check found a difference, 2 bad input or an unusable repo.
"""
import argparse
import os
import re
import subprocess
import sys
import tomllib

HEX = re.compile(r"^#[0-9a-f]{6}$")
OTTY_OUT = "dot_config/otty/themes/omarchy.ottytheme"
NOCTTY_OUT = "dot_config/noctty/omarchy-theme.conf"
NVIM_OUT = "dot_config/nvim/lua/plugins/theme.lua"
STARSHIP_OUT = ".chezmoitemplates/starship-palettes.toml"
NVIM_MAX_BYTES = 64 * 1024


def fail(msg):
    print(f"sync-omarchy-theme: {msg}", file=sys.stderr)
    sys.exit(2)


def parse_ghostty(path):
    """Read the colours out of a Ghostty-format theme file. Returns dict with palette (16), background, foreground..."""
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        fail(f"cannot read {path}: {e.strerror}")
    colors = {}
    palette = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip()
        if key == "palette":
            idx, _, colour = value.partition("=")
            idx, colour = idx.strip(), colour.strip().lower()
            if not idx.isdigit() or not 0 <= int(idx) <= 15:
                fail(f"{path}: bad palette index {idx!r}")
            if not HEX.match(colour):
                fail(f"{path}: palette {idx} is not #rrggbb: {colour!r}")
            palette[int(idx)] = colour
        elif key in ("background", "foreground", "cursor-color", "selection-background", "selection-foreground"):
            colour = value.lower()
            if not HEX.match(colour):
                fail(f"{path}: {key} is not #rrggbb: {value!r}")
            colors[key] = colour
    missing = [i for i in range(16) if i not in palette]
    if missing:
        fail(f"{path}: palette entries missing: {missing}")
    for need in ("background", "foreground"):
        if need not in colors:
            fail(f"{path}: no {need} colour")
    colors["palette"] = [palette[i] for i in range(16)]
    return colors


def read_meta(theme_dir):
    """Theme name and light/dark mode, for the header comment only (never for any colour)."""
    name = "unknown"
    try:
        name = open(os.path.join(os.path.dirname(theme_dir.rstrip("/")), "theme.name"), encoding="utf-8").read().strip() or name
    except OSError:
        pass
    mode = "unknown"
    try:
        mode = tomllib.load(open(os.path.join(theme_dir, "colors.toml"), "rb")).get("mode", mode)
    except (OSError, tomllib.TOMLDecodeError):
        pass
    return name, mode


def render_otty(c, name, mode):
    p = c["palette"]
    rows = ",\n".join("  " + ", ".join(f'"{x}"' for x in p[i:i + 4]) for i in range(0, 16, 4))
    sel = c.get("selection-background"), c.get("selection-foreground")
    out = [
        f"# GENERATED by scripts/sync-omarchy-theme.py from Omarchy's current theme: {name} ({mode}). Do not edit by hand:",
        "# the next theme switch on Omarchy overwrites it. Use with `theme = omarchy` in an Otty config.",
        "[meta]",
        'name = "Omarchy"',
        "",
        "[terminal]",
        f'foreground = "{c["foreground"]}"',
        f'background = "{c["background"]}"',
        f'cursor = "{c.get("cursor-color", c["foreground"])}"',
        f'cursor-text = "{c["background"]}"',
        "palette = [",
        rows + ",",
        "]",
    ]
    if sel[0] and sel[1]:
        out += ["", "[selection]", f'foreground = "{sel[1]}"', f'background = "{sel[0]}"']
    return "\n".join(out) + "\n"


def render_ghostty(c, name, mode):
    out = [
        f"# GENERATED by scripts/sync-omarchy-theme.py from Omarchy's current theme: {name} ({mode}). Do not edit by hand.",
        "# Only the colours: Omarchy's own file also has window-glass settings (opacity, a GTK stylesheet path) that make",
        "# no sense on another machine, so they are left out. Included by config.ghostty (Noctty).",
        f"background = {c['background']}",
        f"foreground = {c['foreground']}",
        f"cursor-color = {c.get('cursor-color', c['foreground'])}",
    ]
    if "selection-background" in c:
        out.append(f"selection-background = {c['selection-background']}")
    if "selection-foreground" in c:
        out.append(f"selection-foreground = {c['selection-foreground']}")
    out.append("")
    out += [f"palette = {i}={colour}" for i, colour in enumerate(c["palette"])]
    return "\n".join(out) + "\n"


def read_neovim_spec(theme_dir):
    """Omarchy's generated neovim.lua, validated: returns its text, or None if the theme has none.
    Only sanity checks (it is Lua we cannot run here): a plain, small, text file that returns a spec table
    and sets a colorscheme. Anything else is refused, so a broken file can never reach the other machines."""
    path = os.path.join(theme_dir, "neovim.lua")
    if not os.path.exists(path):
        return None
    try:
        raw = open(path, "rb").read()
    except OSError as e:
        fail(f"cannot read {path}: {e.strerror}")
    if len(raw) > NVIM_MAX_BYTES or b"\0" in raw:
        fail(f"{path}: too large or not a text file")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        fail(f"{path}: not UTF-8")
    if not re.search(r"^\s*return\s*\{", text, re.M) or "colorscheme" not in text:
        fail(f"{path}: does not look like a LazyVim theme spec (no `return {{` or no colorscheme)")
    return text


def render_nvim(text, name, mode):
    header = (
        f"-- GENERATED by scripts/sync-omarchy-theme.py from Omarchy's current theme: {name} ({mode}). Do not edit by hand:\n"
        "-- the next theme switch on Omarchy overwrites it. Everything below is Omarchy's own neovim.lua, unchanged.\n"
        "-- (On Omarchy this path is Omarchy's symlink instead; chezmoi leaves it alone there.)\n"
    )
    return header + text if text.endswith("\n") else header + text + "\n"


# ── starship: the tiered "pill" colours, derived from Omarchy's colors.toml ───────────────────────────────────────
def _h2rgb(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))


def _rgb2h(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(x * 255))) for x in c)


def _mix(a, b, t):
    """a moved a fraction t of the way toward b (plain sRGB blend)."""
    return _rgb2h(tuple(x + (y - x) * t for x, y in zip(_h2rgb(a), _h2rgb(b))))


def _lum(h):
    f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (f(x) for x in _h2rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    hi, lo = sorted((_lum(a), _lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def _readable(color, against, toward, want):
    """Move `color` toward `toward` in 5% steps until it reaches contrast `want` against `against`."""
    for i in range(21):
        c = _mix(color, toward, i / 20)
        if contrast(c, against) >= want:
            return c
    return toward


def _best_text(on, a, b):
    return a if contrast(a, on) >= contrast(b, on) else b


def _pill(fill, bg, fg):
    """(fill, text) for a segment that has a background: the theme's own background or foreground as the text where one
    reaches 4.5:1 on the fill (nudging the fill lighter or darker if that gets it there); plain black or white otherwise."""
    white, black = "#ffffff", "#000000"
    text = _best_text(fill, bg, fg)
    for t in (text, black, white):
        f = fill if contrast(t, fill) >= 4.5 else _readable(fill, t, black if _lum(t) > _lum(fill) else white, 4.5)
        if contrast(t, f) >= 4.5:
            return f, t
    t = _best_text(fill, black, white)           # unreachable in practice: one of black / white always works
    return fill, t


def _synth_base(accent, mode):
    """A background for the appearance a theme is NOT in (the Mac follows macOS light/dark): the accent's hue, nearly neutral."""
    import colorsys
    h, _, s = colorsys.rgb_to_hls(*_h2rgb(accent))
    return _rgb2h(colorsys.hls_to_rgb(h, 0.12 if mode == "dark" else 0.96, min(s, 0.25)))


def _lin(v):
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def _delin(v):
    v = max(0.0, min(1.0, v))
    return v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055


def oklab(h):
    """sRGB hex -> OKLab (L, a, b). L is perceptual lightness: equal L steps look like equal steps."""
    r, g, b = (_lin(x) for x in _h2rgb(h))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def from_oklab(L, a, b):
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return _rgb2h((_delin(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                   _delin(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                   _delin(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)))


def lightness(h):
    return oklab(h)[0]


STEP = 0.085        # lightness between neighbouring tiers (OKLab L; 0.07 and up is plainly visible side by side)


def _tiers(bg, fg, accent, red, cyan, magenta):
    """One palette. Pills, left to right: OS, directory (= the accent), git, language, duration. The three quiet tiers
    are a ladder of equal perceptual steps (STEP) away from the background, toward the foreground's side, in a tint
    mostly the accent's hue (fading toward the background's), so each is plainly distinct from its neighbours and from
    the terminal background. The OS pill is the accent moved toward the foreground (or the background if that is no
    different) until it differs from the directory pill by more than a step too. Text colours are nudged to >= 4.5:1.
    Why not blend by a percentage of the accent: that gave steps of 1.04-1.1 contrast, and the last tiers vanished."""
    white, black = "#ffffff", "#000000"
    lb, ab, bb = oklab(bg)
    la, aa, ba = oklab(accent)
    sign = 1 if lb < 0.6 else -1                          # dark theme: tiers get lighter away from the background
    ta, tb = ab + (aa - ab) * 0.6, bb + (ba - bb) * 0.6   # the tier tint at full strength (the git tier)
    dir_bg, dir_fg = _pill(accent, bg, fg)
    # the step: STEP, unless that would push the git tier past the lightness where text stops being readable on it
    # (dark theme: L 0.54, light theme: 0.60) or too close to the directory pill (which needs 0.075 of room above it)
    cap = 0.54 if sign > 0 else 0.60
    step = max(0.04, min(STEP, abs(cap - lb) / 3, (abs(lightness(dir_bg) - lb) - 0.075) / 3))
    def tier(k):      # k = 1..3 steps from the background; the tint fades toward the background (the last tier is the calmest)
        f = 0.4 + 0.6 * k / 3
        return from_oklab(max(0.0, min(1.0, lb + sign * step * k)), ab + (ta - ab) * f, bb + (tb - bb) * f)
    git_bg, lang_bg, dur_bg = tier(3), tier(2), tier(1)
    # the OS pill: the accent moved toward the foreground (else the background, else black/white) until, AFTER its text
    # colour has been settled, it differs from the directory pill by more than a step; the best candidate wins if none does
    best = None
    for target in (fg, bg, white if sign > 0 else black, black if sign > 0 else white):
        for i in range(1, 21):
            f, t = _pill(_mix(accent, target, i / 20), bg, fg)
            gap = abs(lightness(f) - lightness(dir_bg))
            if best is None or gap > best[0]:
                best = (gap, f, t)
            if gap >= STEP + 0.02:
                break
        else:
            continue
        break
    os_bg, os_fg = best[1], best[2]
    extreme = white if sign > 0 else black                # text is pushed toward this if the theme's own colours fall short
    text = _readable(_mix(fg, accent, 0.25), git_bg, extreme, 4.5)
    return {
        "love": _readable(red, bg, fg, 3.0), "foam": _readable(cyan, bg, fg, 3.0), "iris": _readable(magenta, bg, fg, 3.0),
        "pill_os_bg": os_bg, "pill_os_fg": os_fg, "pill_dir_bg": dir_bg, "pill_dir_fg": dir_fg,
        "pill_git_bg": git_bg, "pill_lang_bg": lang_bg, "pill_dur_bg": dur_bg,
        "pill_text": text, "pill_change": _readable(red, git_bg, extreme, 3.5),
    }


def starship_palettes(c):
    """c: validated colors.toml values. Returns {palette name: palette}: `omarchy` (the theme's own appearance, used by
    every machine but the Mac) plus `omarchy-dark` and `omarchy-light` (the Mac follows macOS's appearance; the one that
    does not match the theme gets a synthesised background and an accent adjusted to stay readable on it)."""
    mode, bg, fg, accent = c["mode"], c["background"], c["foreground"], c["accent"]
    own = _tiers(bg, fg, accent, c["red"], c["cyan"], c["magenta"])
    other = "light" if mode == "dark" else "dark"
    obg = _synth_base(accent, other)
    ofg = "#f2f2f2" if other == "dark" else "#1a1a1a"
    oacc = _readable(accent, obg, ofg, 3.0)
    opposite = _tiers(obg, ofg, oacc, *(_readable(c[k], obg, ofg, 3.0) for k in ("red", "cyan", "magenta")))
    return {"omarchy": own, f"omarchy-{mode}": own, f"omarchy-{other}": opposite}


def read_colors_toml(theme_dir):
    """The values the starship palettes need, or None if colors.toml is absent or lacks one (that output is then skipped).
    A value that is present but not #rrggbb is refused (nothing is written)."""
    path = os.path.join(theme_dir, "colors.toml")
    try:
        d = tomllib.load(open(path, "rb"))
    except OSError:
        return None
    except tomllib.TOMLDecodeError as e:
        fail(f"{path}: not valid TOML ({e})")
    keys = ("background", "foreground", "accent", "red", "cyan", "magenta")
    out = {}
    for k in keys:
        if k not in d:
            return None
        v = str(d[k]).strip().lower()
        if not HEX.match(v):
            fail(f"{path}: {k} is not #rrggbb: {d[k]!r}")
        out[k] = v
    out["mode"] = d["mode"] if d.get("mode") in ("dark", "light") else ("dark" if _lum(out["background"]) < 0.4 else "light")
    return out


def render_starship(c, name):
    pals = starship_palettes(c)
    out = [
        f"# GENERATED by scripts/sync-omarchy-theme.py from Omarchy's current theme: {name} ({c['mode']}). Do not edit by hand:",
        "# the next theme switch on Omarchy overwrites it. Included by starship-tiered.toml (rendered into ~/.config/starship*.toml).",
        "# omarchy = the theme's own appearance; omarchy-dark / omarchy-light = what the Mac uses for macOS dark / light mode.",
    ]
    for pname, pal in pals.items():
        out += ["", f"[palettes.{pname}]"] + [f'{k:<13}= "{v}"' for k, v in pal.items()]
    return "\n".join(out) + "\n"


def default_repo():
    try:
        r = subprocess.run(["chezmoi", "source-path"], capture_output=True, text=True, timeout=20)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    return os.path.expanduser("~/.local/share/chezmoi")


def write_if_changed(path, content, check):
    try:
        if open(path, encoding="utf-8").read() == content:
            return "unchanged"
    except OSError:
        pass
    if check:
        return "would change"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(content)
    os.replace(tmp, path)
    return "written"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--theme-dir", default=os.path.expanduser("~/.local/state/omarchy/current/theme"))
    ap.add_argument("--repo", default=None)
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    repo = a.repo or default_repo()
    if not os.path.isfile(os.path.join(repo, ".chezmoi.toml.tmpl")):
        fail(f"{repo} does not look like the dotfiles repo (no .chezmoi.toml.tmpl)")
    colors = parse_ghostty(os.path.join(a.theme_dir, "ghostty.conf"))   # validates everything BEFORE any write
    nvim_text = read_neovim_spec(a.theme_dir)                            # also validated before any write
    starship_in = read_colors_toml(a.theme_dir)                          # also validated before any write
    name, mode = read_meta(a.theme_dir)
    results = {
        OTTY_OUT: write_if_changed(os.path.join(repo, OTTY_OUT), render_otty(colors, name, mode), a.check),
        NOCTTY_OUT: write_if_changed(os.path.join(repo, NOCTTY_OUT), render_ghostty(colors, name, mode), a.check),
    }
    if nvim_text is None:
        print(f"{'skipped':13} {NVIM_OUT} (this theme has no neovim.lua)", file=sys.stderr)
    else:
        results[NVIM_OUT] = write_if_changed(os.path.join(repo, NVIM_OUT), render_nvim(nvim_text, name, mode), a.check)
    if starship_in is None:
        print(f"{'skipped':13} {STARSHIP_OUT} (no complete colors.toml in this theme)", file=sys.stderr)
    else:
        results[STARSHIP_OUT] = write_if_changed(os.path.join(repo, STARSHIP_OUT), render_starship(starship_in, name), a.check)
    for rel, status in results.items():
        print(f"{status:13} {rel}", file=sys.stderr)
    if a.check and any(s == "would change" for s in results.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()
