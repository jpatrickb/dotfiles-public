# Shared by bash and zsh: PATH, environment and aliases that must be identical on every machine.
# Sourced from ~/.zshrc (Ubuntu, Mac) and ~/.bashrc (the Arch family, including Omarchy), after the
# shell's own defaults, so what is set here wins. Keep this file free of shell-specific syntax at top
# level (no zsh-only or bash-only constructs); shell-specific setup stays in .zshrc / bash-defaults.
# Functions live in functions.sh. See docs for why each choice was made.

# ── PATH ────────────────────────────────────────────────────────────────────────────────────────────────
# Add a directory to the front of PATH only if it exists and is not already there.
_dotfiles_path_prepend() {
  [ -d "$1" ] || return 0
  case ":$PATH:" in *":$1:"*) ;; *) PATH="$1:$PATH" ;; esac
}
# get.chezmoi.io's installer picks from whatever is already on PATH at bootstrap time, so on a brand-new
# machine it can land in ~/bin instead of ~/.local/bin. Cover both.
_dotfiles_path_prepend "$HOME/bin"
_dotfiles_path_prepend "$HOME/.fzf/bin"
_dotfiles_path_prepend "$HOME/.atuin/bin"
_dotfiles_path_prepend "$HOME/.antigravity/antigravity/bin"
_dotfiles_path_prepend "$HOME/google-cloud-sdk/bin"      # Linux tarball install; Homebrew's cask covers the Mac
_dotfiles_path_prepend "$HOME/.local/bin"
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"   # uv / local env, if present
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"           # cargo / rustup
_dotfiles_path_prepend "/opt/homebrew/opt/rustup/bin"       # Mac: rustup toolchain shims

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) [ -d "$PNPM_HOME/bin" ] && export PATH="$PNPM_HOME/bin:$PATH" ;;
esac

# ── Editor / pagers ─────────────────────────────────────────────────────────────────────────────────────
# nvim everywhere. Omarchy's default is `omarchy-launch-editor --inline`, which also resolves to nvim unless
# Omarchy's default editor is changed; setting it explicitly keeps every machine the same.
export EDITOR="nvim"
export VISUAL="nvim"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export MANROFFOPT="-c"

# ── fzf ─────────────────────────────────────────────────────────────────────────────────────────────────
# Colors are not set here: fzf then uses the terminal's own palette, so it follows the terminal theme.
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
if command -v fzf >/dev/null 2>&1 && command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
fi

# ── Aliases: listing (yours: ls short, ll long, la all, lt tree) ─────────────────────────────────────────
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first --icons'
  alias ll='eza -l --group-directories-first --icons'
  alias la='eza -la --group-directories-first --icons'
  alias lt='eza --tree --group-directories-first --icons'
fi

# ── Aliases from Omarchy, shared everywhere ─────────────────────────────────────────────────────────────
# cd that falls back to zoxide: `cd proj` jumps to a matching directory when no exact path exists.
# (`z` itself comes from `zoxide init`, done in .zshrc / bash-defaults.)
if command -v zoxide >/dev/null 2>&1; then
  alias cd="zd"
  zd() {
    if (( $# == 0 )); then
      builtin cd ~ || return
    elif [[ -d $1 ]]; then
      builtin cd "$1" || return
    else
      if ! z "$@"; then
        echo "Error: Directory not found"
        return 1
      fi

      printf "\U000F17A9 "
      pwd
    fi
  }
fi

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias g='git'
alias gcm='git commit -m'
alias gcam='git commit -a -m'
alias d='docker'
alias t='tmux attach || tmux new -s Work'
alias h='herdr'

# Fuzzy file helpers: ff previews with bat, eff opens the pick in $EDITOR, sff scp's a recent file somewhere.
alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
alias eff='$EDITOR "$(ff)"'
sff() {
  if [ $# -eq 0 ]; then echo "Usage: sff <destination> (e.g. sff host:/tmp/)"; return 1; fi
  local file listing
  # Newest files first. GNU find has -printf; BSD find (macOS) does not, so use stat there.
  if find /dev/null -printf '' >/dev/null 2>&1; then
    listing=$(find . -type f -printf '%T@\t%p\n' | sort -rn | cut -f2-)
  else
    listing=$(find . -type f -exec stat -f '%m	%N' {} + | sort -rn | cut -f2-)
  fi
  file=$(printf '%s\n' "$listing" | ff) && [ -n "$file" ] && scp "$file" "$1"
}

# ── Your own aliases ────────────────────────────────────────────────────────────────────────────────────
alias tf='terraform'
command -v acli >/dev/null 2>&1 && { alias jira='acli jira'; alias conf='acli confluence'; }

# ── Clipboard and open ──────────────────────────────────────────────────────────────────────────────────
# pbcopy/pbpaste: macOS has native binaries for both, so only alias them where xclip / the Windows
# clipboard actually exist; this never shadows the real macOS commands.
if command -v xclip >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
  alias pbcopy='xclip -selection clipboard'
  alias pbpaste='xclip -selection clipboard -o'
elif command -v clip.exe >/dev/null 2>&1; then
  # WSL without an X display: use the Windows clipboard directly.
  alias pbcopy='clip.exe'
  alias pbpaste='powershell.exe -NoProfile -Command Get-Clipboard | tr -d "\r"'
fi
# open: Omarchy defines its own detached `open` function, so leave that alone there.
if [ ! -d /usr/share/omarchy ]; then
  command -v xdg-open >/dev/null 2>&1 && alias open='xdg-open'
  # WSL: no xdg-open/wslview by default; wsl-open (from ~/.local/bin) hands URLs/files to Windows.
  # $BROWSER is what tools like `gh auth login` use to open the browser.
  if [ -n "$WSL_DISTRO_NAME" ] && command -v wsl-open >/dev/null 2>&1; then
    export BROWSER=wsl-open
    alias open='wsl-open'
  fi
fi
