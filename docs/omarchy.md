# Omarchy

Omarchy is the **source of truth for colours**, and the reference for how things should feel. These dotfiles layer
on top of it instead of replacing it: where Omarchy already provides something (tmux base config, starship, foot,
btop, its themes), the repo keeps Omarchy's version and adds only what you want on top. Every other machine
follows Omarchy's theme through this repo.

## How a machine is classified

`chezmoi init` detects two things (no prompt) and stores them in `~/.config/chezmoi/chezmoi.toml`:

| | values |
|---|---|
| `family` | `arch` (Arch, Arch on WSL, **Omarchy**), `debian` (Ubuntu), `mac`, `other` |
| `env` | `omarchy` (`/usr/share/omarchy` exists), `wsl`, `native` |

Templates and `.chezmoiignore` branch on these. After pulling a change to the detection you must re-run
`chezmoi init`; chezmoi tells you when. Check what a machine is with `chezmoi data | grep -E 'family|env'`.

## What is whose on Omarchy

| Thing | Owner | Notes |
|---|---|---|
| Shell | repo | **bash** (the arch family), with ble.sh 0.4 for suggestions and highlighting. zsh is only used on Ubuntu and the Mac. `.bashrc` is edited in place by a marked block; Omarchy's own lines stay |
| tmux | repo, on Omarchy's base | Omarchy's config verbatim plus guards, extended keys and prompt-jump bindings. No TPM, no plugins |
| starship | repo | the tiered "pill" prompt, with colours **generated from the Omarchy theme** on every theme switch (see [Theme sync](#theme-sync) and [The prompt's colours](#the-prompts-colours)) |
| bat, delta, fzf, eza | repo | follow the terminal's ANSI colours, so they follow the Omarchy theme with nothing to sync |
| foot | Omarchy | the repo adds one marked block: copy a selection to the system clipboard |
| btop | Omarchy | the repo's btop config is for the other machines only |
| fastfetch | both | the About window stays Omarchy's; the shell banner uses the repo's `banner.jsonc` |
| Neovim | repo | LazyVim as Omarchy ships it, plus yours. `lua/plugins/theme.lua` stays Omarchy's symlink. See [neovim.md](neovim.md) |
| Packages | Omarchy's tools | `run_once_before_01b-omarchy-packages.sh` uses `omarchy-pkg-add` (only what is missing). It never runs `pacman -Syu`: system updates stay in Omarchy's own update flow, which takes snapshots |
| Otty, Noctty, WezTerm | not used here | Otty is the Mac's terminal, Noctty is Windows'; WezTerm is retired |

## Adopting this on an existing Omarchy machine

Nothing is applied until you say so. A backup of the files involved was taken before the work started (see below).

```bash
cd ~/.local/share/chezmoi
git status                              # should be clean
git switch omarchy-revamp               # the branch with all the work (not pushed anywhere)
chezmoi init                            # first time on this machine: asks two questions (AWS CLI, GCP CLI); answer no
chezmoi data | grep -E 'family|env'     # expect: arch / omarchy
chezmoi apply --dry-run --verbose | less    # read what would change
chezmoi diff | less                         # the same, as a diff
chezmoi apply
```

chezmoi has no record yet of what it wrote on this machine, so for every existing file that differs it will ask
what to do (overwrite, skip, diff, all). Answer `diff` when unsure; nothing is lost either way (see *Rolling back*).

What a first apply does on Omarchy: writes the config files; runs the Omarchy package script (installs `lazygit`,
`btop`, `git-delta`, `atuin`, `direnv`, `bash-preexec` and, from the AUR, `blesh-git` (replacing Arch's older `blesh` if it is installed); it may ask for your
sudo password and builds `blesh-git` from its PKGBUILD); skips every zsh-only and apt/pacman-upgrade script. Then open a **new** shell and
a new terminal, run `nvim` once (plugins install; restart after Mason finishes) and `tmux`.

### Rolling back

- A change you do not like: `chezmoi git -- log`, then revert the commit or `git switch main` and `chezmoi apply`.
- Everything, to the state before the work started: `~/.local/share/dotfiles-revamp-backup/restore.sh` shows what it
  would do (dry run). `restore.sh --apply` restores the saved files **and deletes files that did not exist then**,
  so read the dry run first.

## Theme sync

You switch theme the Omarchy way (`omarchy-theme-set`, the menu, ...). Omarchy then runs every script in
`~/.config/omarchy/hooks/theme-set.d/`; this repo installs one there, `20-dotfiles-theme-sync`. It runs
`scripts/sync-omarchy-theme.py`, which writes four files **into the repo working tree**:

| File | Used by |
|---|---|
| `dot_config/otty/themes/omarchy.ottytheme` | Otty (Mac) |
| `dot_config/noctty/omarchy-theme.conf` | Noctty (Windows) |
| `dot_config/nvim/lua/plugins/theme.lua` | Neovim on every machine except Omarchy |
| `.chezmoitemplates/starship-palettes.toml` | the starship prompt on every machine (see below) |

On Omarchy the hook then also runs `chezmoi apply` on that one file, `~/.config/starship.toml`, so the prompt follows the
new theme immediately (the other three files are only for the other machines). It never commits and never pushes, and it can never fail a theme switch (it always exits 0; the result of the last run
is in `~/.local/state/dotfiles-theme-sync.log`). Bad or incomplete input is refused before anything is written, so a
half-generated theme cannot reach the other machines.

To bring the other machines along:

```bash
chezmoi git -- status                   # on Omarchy: the three generated files show as modified
chezmoi git -- add -A && chezmoi git -- commit -m "theme: <name>" && chezmoi git -- push
# on each other machine:
chezmoi git -- pull && chezmoi apply
```

On WSL the apply also copies the Noctty files to Windows. Terminals pick the new colours up on reload
(Neovim: the next start; Otty: restart it if the colours do not change, not verified). Run the generator by hand any time with
`python3 ~/.local/share/chezmoi/scripts/sync-omarchy-theme.py` (add `--check` to only see whether anything would change).

## The prompt's colours

The starship prompt is a row of connected "pills" that fade from the accent toward the terminal background: OS,
directory (the accent), git, language versions, command duration. `scripts/sync-omarchy-theme.py` derives them from the
theme's `colors.toml` (`accent`, `background`, `foreground`, `mode`, plus `red`, `cyan`, `magenta` for the prompt
character and git changes). The tiers are built in **perceptual lightness** (OKLab), not as a percentage of the accent,
because a percentage blend made the last pills melt into the terminal background:

| Pill | Colour |
|---|---|
| directory | the accent (nudged lighter or darker only if its text would be under 4.5:1) |
| git, language, duration | three equal lightness steps (about 0.085, at least 0.07) away from the terminal background, in a tint of the accent that fades toward the background; the step shrinks a little when the accent is close to the background or when text would stop being readable |
| OS | the accent moved toward the foreground (or the background) until it differs from the directory pill by a full step |
| text | the foreground with a hint of the accent on the three quiet pills; the git-changes marker is the theme's red, kept readable on the git pill |

It writes three palettes into `.chezmoitemplates/starship-palettes.toml`: `omarchy` (the theme's own appearance, used on
every machine except the Mac), and `omarchy-dark` / `omarchy-light` for the Mac, whose `~/.config/starship-dark.toml` and
`starship-light.toml` are picked by macOS appearance (`.zshrc`). The one that does not match the theme gets a synthesised
near-neutral background in the accent's hue and an accent adjusted to stay readable on it. The Mac's terminal itself still
uses Otty's own themes, so a theme's accent can sit on a terminal background that is not the Omarchy one.
`.test/starship-tiers.sh` checks every installed Omarchy theme and palette: text at least 4.5:1 on every pill, a lightness step of at
least 0.07 between every pair of neighbouring pills and between the last pill and the background, and a real starship render.

## When Omarchy updates

- **Packages and system:** update the Omarchy way. chezmoi never upgrades the system on Omarchy.
- **Config files the repo copied** (the Neovim helper files, the tmux base, the foot file) are snapshots of what
  Omarchy shipped when you adopted them, so an Omarchy update to those does not reach you automatically.
  `.test/nvim.sh` compares the seven copied Neovim files with `/etc/skel/.config/nvim` and prints a note when Omarchy has
  changed one; compare `/usr/share/omarchy/config/tmux/tmux.conf` and `.../foot/foot.ini` with the repo's versions
  occasionally.
- **Fonts:** `foot.ini` is edited by Omarchy's font tool; the repo's block is separate, so a font change survives.

## Troubleshooting

- *A theme switch did not update the repo:* `cat ~/.local/state/dotfiles-theme-sync.log`.
- *`chezmoi apply` wants to overwrite `~/.config/nvim/lua/plugins/theme.lua`:* it must not (that is Omarchy's symlink,
  and the file is ignored on Omarchy). It means `chezmoi data` does not say `env = omarchy`; run `chezmoi init`.
- *Suggestions or highlighting missing in bash:* `blesh-git` did not install, or the installed ble.sh is older than 0.4
  (`pacman -Q blesh blesh-git`; the Arch package `blesh` is 0.3.4). Fix: `omarchy-pkg-aur-add blesh-git` (remove `blesh`
  first, they conflict), then a new shell. Bash still works without it, just with no suggestions.
- *Line editing in bash is vi style* (`set -o vi`; Esc for normal mode). The mode shows in the prompt character as in zsh: `❯` in insert mode, `❮` in the iris colour in normal mode (ble.sh's own `-- INSERT --` line is off). **Ctrl+G** (either mode) and
  **v** (normal mode) open the current command line in `$EDITOR` (nvim); save and quit runs it. ble.sh's autosuggestion is
  drawn as grey letters only (`ble-face auto_complete='fg=244'`; ble.sh's own default is a grey block behind each letter).
  To go back to emacs keys, delete the `set -o vi` line in `modify_dot_bashrc`.
- *Reload bash with `exec bash` (or open a new terminal), not `source ~/.bashrc`:* it is the way ble.sh documents, and
  re-sourcing inside a running ble.sh session can misbehave.
- *About the ble.sh setup.* The `.bashrc` block loads ble.sh only if it is **0.4 or newer**. Arch's `blesh` (0.3.4) is
  deliberately left out because it cannot draw the starship prompt: it takes a 24-bit colour (`38;2;r;g;b`) apart and
  treats r, g and b as separate colour codes, so the generated hex colours come out as other colours (lime separators, a
  lavender block). It also leaves xterm's modifyOtherKeys on while programs like `sudo` or `yay` run, so on foot a capital
  letter typed into a password prompt arrives as an escape sequence (`^[[27;2;65~`) and the password is rejected. 0.4 has
  neither problem, and its own hooks for starship, direnv and atuin, so the prompt workaround older versions needed is
  gone. ble.sh is loaded after Omarchy's rc so its `bind` interception does not print warnings. `.test/ble.sh` drives a
  real interactive session (with `COLORTERM=truecolor`) and asserts the exact palette colours reach the terminal.
