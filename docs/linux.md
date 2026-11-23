# Ubuntu / Linux (native)

Same as the WSL guide, minus the Windows steps. This is the path the container test covers. The shell here is
**zsh**. (Arch-based systems use bash; on Omarchy read [omarchy.md](omarchy.md) instead.)

1. Install chezmoi and apply from the public mirror (no key or login; accept the `sudo`
   prompt; takes a few minutes):
   ```bash
   sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply https://github.com/jpatrickb/dotfiles-public.git
   ```
   This installs apt packages, Neovim, Go, Rust, Terraform and shell tools. The font is
   installed locally if a GUI is present.
   `chezmoi init` asks whether to install the AWS CLI and the GCP CLI (default: no). To add
   either later, run `chezmoi init --prompt`, answer yes, then `chezmoi apply`.
2. Edit `~/.gitconfig.local` (created automatically): set your git name and email.
3. Open a new shell, then:
   ```bash
   hash -r && chezmoi status        # expect only R lines
   ```
4. First launch: `tmux` (nothing to install: the status bar uses your terminal's colours, so there is no plugin step),
   then `nvim`, then `:Lazy restore` if anything looks half-installed; wait for `:Mason` to finish, then
   **restart nvim** (formatters and language servers are not ready until then), and run `:LspCopilotSignIn` once.
   More in [neovim.md](neovim.md).

## Alternative: private repo (needs the deploy key)

Use this on a machine where you can bring `dotfiles_deploy` in. Create the SSH alias
`github-dotfiles` (Host github.com, User git, IdentityFile ~/.ssh/dotfiles_deploy,
IdentitiesOnly yes), check `ssh -T git@github-dotfiles`, then run the install command
above with `git@github-dotfiles:jpatrickb/dotfiles.git` instead of the https URL. The
private repo is the one you can push to.

Optional: `~/.secrets` for API keys.
