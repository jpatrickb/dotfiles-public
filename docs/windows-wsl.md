# Windows laptop (WSL)

Three parts: Windows, then inside WSL, then first launch. The WSL part is tested in a
container; the Windows part is not, so expect to adjust it.

## A. On Windows (PowerShell)

1. Install WSL and Ubuntu (may need admin/IT approval and a reboot):
   ```powershell
   wsl --list --online              # confirm the exact name
   wsl --install -d Ubuntu-26.04
   ```
2. Install **Noctty**, the terminal used on Windows: `winget install --id AmanThanvi.noctty -e`. (Otty is the Mac's
   terminal; it is not used on Windows for now. It is parked in the repo and can be switched back on, see
   `.chezmoiignore`.)
3. Noctty opens `wsl.exe`, which starts your **default** WSL distro. Make Ubuntu the default if it is not:
   `wsl --set-default Ubuntu-26.04` (or edit `command = wsl.exe -d Ubuntu-26.04` in `~/.config/noctty/config.ghostty`).

## B. Inside WSL

The public mirror needs no key or login.

1. Install chezmoi and apply (accept the `sudo` prompt; takes a few minutes):
   ```bash
   sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply https://github.com/jpatrickb/dotfiles-public.git
   ```
   This installs apt packages, Neovim, Go, Rust, Terraform, shell tools and the font, and
   copies the Noctty config and colour palette to Windows. The shell is zsh.
   `chezmoi init` asks whether to install the AWS CLI and the GCP CLI (default: no). To add
   either later, run `chezmoi init --prompt`, answer yes, then `chezmoi apply`.
2. Edit `~/.gitconfig.local` (created automatically): set your git name and email.
3. **Restart WSL so every shell starts fresh.** The terminal you ran the install in began before the shell config
   existed, so it does not have the new PATH (`~/.local/bin`, which holds `herdr` and others). In Windows PowerShell run
   `wsl --terminate Ubuntu` (use the name `wsl -l` shows for your distro), then open it again. Then:
   ```bash
   hash -r && chezmoi status        # expect only R lines
   ```

## Alternative: private repo (needs the deploy key)

Use this on a machine where you can bring `dotfiles_deploy` in. Create the SSH alias
`github-dotfiles` (Host github.com, User git, IdentityFile ~/.ssh/dotfiles_deploy,
IdentitiesOnly yes), check `ssh -T git@github-dotfiles`, then run the install command
above with `git@github-dotfiles:jpatrickb/dotfiles.git` instead of the https URL. The
private repo is the one you can push to.

## C. First launch

1. **Restart the terminal app** so the Nerd Font appears.
2. Confirm the config landed: `%LOCALAPPDATA%\noctty\config.ghostty` and `%LOCALAPPDATA%\noctty\omarchy-theme.conf` (the
   colours). If you had edited the Windows copy by hand, your version was saved next to it as `config.ghostty.bak`.
   Reload with Ctrl+Shift+, or restart Noctty.
3. Shift+Enter should insert a newline in Claude Code and Neovim (the config binds it, and Alt+Shift+Enter).
4. `tmux` (nothing to install; there is no plugin step).
5. `nvim`, then `:Lazy restore` if anything looks half-installed; wait for `:Mason` to finish, then
   **restart nvim** (formatters and language servers are not ready until then), and run `:LspCopilotSignIn` once.
   More in [neovim.md](neovim.md).

Colours follow Omarchy's theme; see [omarchy.md](omarchy.md#theme-sync). Old leftover: delete
`%USERPROFILE%\.wezterm.lua` by hand (WezTerm is retired; the repo cannot reach that file from WSL).

Optional: `~/.secrets` for API keys.
