# System-summary banner shown when a new interactive shell starts. Shared by bash and zsh; sourced LAST by
# ~/.zshrc and by the managed block in ~/.bashrc (before ble.sh attaches).
#   - local terminal: the full fastfetch layout (~/.config/fastfetch/banner.jsonc)
#   - over SSH:       one compact line (compact.jsonc), so remote logins stay quiet
#   - inside tmux or herdr panes: nothing (every new pane/tab would repeat it)
# The layout is always passed with -c on purpose: Omarchy has no ~/.config/fastfetch/config.jsonc, so that its
# About window keeps its own layout (see dot_config/fastfetch/banner.jsonc).

_dotfiles_banner() {
  case $- in *i*) ;; *) return 0 ;; esac
  command -v fastfetch >/dev/null 2>&1 || return 0
  [ -n "${TMUX:-}" ] && return 0        # tmux pane
  [ -n "${HERDR_ENV:-}" ] && return 0   # herdr pane (herdr sets HERDR_ENV=1 in every pane)

  local dir="$HOME/.config/fastfetch"
  if [ -n "${SSH_CONNECTION:-}" ]; then
    [ -r "$dir/compact.jsonc" ] || return 0
    fastfetch -c "$dir/compact.jsonc" --pipe false 2>/dev/null \
      | awk 'NF { if (n++) printf "  \033[90m·\033[0m  "; printf "%s", $0 } END { if (n) print "" }'
  elif [ -r "$dir/banner.jsonc" ]; then
    fastfetch -c "$dir/banner.jsonc"
  else
    fastfetch
  fi
}

_dotfiles_banner
unset -f _dotfiles_banner
