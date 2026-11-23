# Mac

1. Install Homebrew, then chezmoi: `brew install chezmoi git`
2. Key and SSH alias (copy `dotfiles_deploy` from another machine into `~/.ssh`):
   ```bash
   chmod 600 ~/.ssh/dotfiles_deploy
   cat >> ~/.ssh/config <<'EOT'
   Host github-dotfiles
     HostName github.com
     User git
     IdentityFile ~/.ssh/dotfiles_deploy
     IdentitiesOnly yes
   EOT
   chmod 600 ~/.ssh/config
   ssh -T git@github-dotfiles       # answer "yes" once; must report success
   ```
3. Install **Otty**, the Mac's terminal (Windows uses Noctty for now): download the installer from Otty's website (docs:
   docs.otty.sh). Open it once so it creates `~/.config/otty/config.toml`; the repo's settings are included from there.
4. Fetch the repo, install the tools, then apply:
   ```bash
   chezmoi init git@github-dotfiles:jpatrickb/dotfiles.git
   brew bundle --file="$(chezmoi source-path)/Brewfile"
   chezmoi apply
   ```
   Optional cloud CLIs: `brew bundle --file="$(chezmoi source-path)/Brewfile.aws"` and/or
   `Brewfile.gcp`.
   The font and Terminal.app profile are set by scripts (macOS may ask to let the script
   control Terminal); Otty reads its own settings from the repo (font, theme `omarchy`, left Option as Alt for tmux and
   herdr shortcuts, Shift+Enter).
5. Edit `~/.gitconfig.local` (created automatically): set your git name and email.
6. Open a new shell **in Otty**, then:
   ```bash
   hash -r && chezmoi status        # expect only R lines
   ```
7. First launch: `tmux` (no plugin step), then `nvim`, then `:Lazy restore` if anything looks half-installed; wait for `:Mason` to finish, then
   **restart nvim** (formatters and language servers are not ready until then), and run `:LspCopilotSignIn` once.
   More in [neovim.md](neovim.md).

The Mac's shell is zsh. The Mac keeps its own look rather than following Omarchy's theme: Otty uses the theme in your
own `~/.config/otty/config.toml` (tracked in the repo), and the prompt is the tiered Rose Pine one, which switches
between its dark and light versions with the macOS appearance.

Otty rewrites `config.toml` when you change a setting in its window. After changing something there, run
`chezmoi re-add ~/.config/otty/config.toml` so the repo copy stays current.

Optional: `~/.secrets` for API keys.
