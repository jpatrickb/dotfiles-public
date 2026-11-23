# dotfiles (chezmoi)

Shell, nvim, tmux, terminal and tool config. Source lives in `~/.local/share/chezmoi`,
`chezmoi apply` writes it into `~`, and GitHub (`origin/main`) syncs machines.

**Omarchy is the reference machine and the source of truth for colours.** The other machines follow its theme through this
repo. Machines are classified automatically (`family`: arch, debian, mac; `env`: omarchy, wsl, native), so one repo
serves all of them: bash on the Arch family (including Omarchy), zsh on Ubuntu and the Mac; Otty on the Mac, Noctty on Windows,
foot on Omarchy; LazyVim everywhere.

## Set up a new machine

Follow **one** guide, top to bottom:

| Machine | Guide |
|---|---|
| Omarchy | [docs/omarchy.md](docs/omarchy.md) |
| Windows laptop (WSL, Ubuntu) | [docs/windows-wsl.md](docs/windows-wsl.md) |
| Windows laptop (WSL, Arch) | [docs/arch-wsl.md](docs/arch-wsl.md) |
| Mac | [docs/mac.md](docs/mac.md) |
| Ubuntu / Linux | [docs/linux.md](docs/linux.md) |

## Guides

- [docs/omarchy.md](docs/omarchy.md): how Omarchy and the repo share the work, adopting it, theme sync, rolling back.
- [docs/neovim.md](docs/neovim.md): the LazyVim setup, key cheat sheet (neo-tree, buffers, pickers), updating plugins.

## Daily

```bash
chezmoi git -- pull               # start; apply only if status is clean
chezmoi edit --apply <file>       # edit here, not in ~
chezmoi status                    # end; M or MM → diff, then add or apply
chezmoi add <file> && chezmoi git -- commit -am "msg" && chezmoi git -- push
```

A history-free public snapshot lives at `jpatrickb/dotfiles-public` (read-only, for machines
without GitHub access). Refresh it after pushing here: `scripts/publish-public.sh`.

Keep Neovim ≥ 0.12 everywhere so one `lazy-lock.json` fits all.

**Theme:** change it on Omarchy. A hook regenerates the Otty, Noctty and Neovim theme files in this repo (never
committing or pushing). Then `chezmoi git -- add -A && chezmoi git -- commit -m "theme" && chezmoi git -- push`, and on the
other machines `chezmoi git -- pull && chezmoi apply`. Details in [docs/omarchy.md](docs/omarchy.md#theme-sync).

After pulling a change to the machine detection (`.chezmoi.toml.tmpl`), run `chezmoi init` again; chezmoi tells you.

## Testing

Two layers. The fast ones run anywhere with chezmoi installed and use throwaway homes: they never touch your real
files (several prove it with a checksum).

| Command | Checks |
|---|---|
| `.test/detect.sh` | machine classification (family / env) |
| `.test/shell.sh`, `bashrc.sh`, `zshrc.sh`, `banner.sh` | the shared shell config in bash and zsh, the `.bashrc` block, the banner |
| `.test/ble.sh` | a real interactive bash in a pseudo-terminal with ble.sh attached: prompt and its exact colours, direnv, warnings, nested shells, which ble.sh versions are loaded (Omarchy with ble.sh 0.4+ only; skipped elsewhere) |
| `.test/tmux.sh`, `starship.sh`, `starship-tiers.sh` | tmux config (real tmux servers on private sockets), the starship prompt, the generated prompt colours across every Omarchy theme |
| `.test/terminals.sh`, `foot.sh`, `theme-sync.sh` | Otty/Noctty files, the WSL-to-Windows copy scripts (against a fake drive), the foot block, the Omarchy theme sync |
| `.test/nvim.sh` | the Neovim config: placement per machine type, then a real headless Neovim in four situations. First run installs ~70 plugins into `~/.cache/dotfiles-nvim-test` (needs network), later runs take about two minutes |
| `.test/packages-arch.sh` | every package name in the Arch script exists |
| `.test/docs.sh` | every link and `#anchor` in the docs resolves; no retired setup is recommended |

`.test/run.sh` is the slow end-to-end one: it applies your working copy (uncommitted changes included) to a fresh
Ubuntu 26.04 container (`DISTRO=arch` for Arch) and runs `.test/check.sh`: tools, shell and tmux startup, Neovim
plugins from the lock file, Mason tools, formatters. `.test/run.sh shell` drops you into the container afterwards.
It needs Docker running, and cannot test the Windows-side steps, Omarchy or the Mac.
