# Shell functions shared by bash and zsh (sourced after common.sh).
#
# Ported from Omarchy's default/bash/fns/* so the same helpers exist on every machine. Changes from the
# originals, all so they behave the same in zsh (Ubuntu, Mac) as in bash (Arch family):
#   - zsh arrays are 1-based and an unmatched glob is an error, so the array/glob-heavy functions switch on
#     `ksh_arrays` and `null_glob` locally under zsh (`setopt local_options` only lasts for that function).
#   - ssh(): the positional-parameter copy is called `all_args`, not `argv` (in zsh `argv` IS $@, so the
#     `shift`s below would empty it).
#   - printf -v / %q are replaced by _dotfiles_quote, which uses zsh's own ${(q)...} under zsh.
#   - rsw/lsw/dsw only exist on Linux (they need setsid, inotifywait and `pgrep -a`).
#   - tdl: Omarchy's version ends with `tmux select-pane -t "$opencode_pane"`, a variable that is never set
#     there (it belongs to tds); fixed to focus the editor pane.
# Dependencies, in case something prints "command not found": ga needs mise, gd needs gum, hdl/hds/hsl need
# herdr and jq, tdl/tds/tsl need tmux, rsw needs rsync and inotify-tools.

# Quote one word so it can be pasted back into a command line (bash: printf %q, zsh: ${(q)...}).
_dotfiles_quote() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    printf '%s' "${(q)1}"
  else
    printf '%q' "$1"
  fi
}

# ── git worktrees ───────────────────────────────────────────────────────────────────────────────────────
# Create a new worktree and branch from within current git directory.
ga() {
  if [[ -z "$1" ]]; then
    echo "Usage: ga [branch name]"
    return 1
  fi

  local branch="$1"
  local base="$(basename "$PWD")"
  local wt_path="../${base}--${branch}"

  git worktree add -b "$branch" "$wt_path"
  mise trust "$wt_path"
  cd "$wt_path"
}

# Remove worktree and branch from within active worktree directory.
gd() {
  if gum confirm "Remove worktree and branch?"; then
    local cwd base branch root worktree

    cwd="$(pwd)"
    worktree="$(basename "$cwd")"

    # split on first `--`
    root="${worktree%%--*}"
    branch="${worktree#*--}"

    # Protect against accidentally nuking a non-worktree directory
    if [[ "$root" != "$worktree" ]]; then
      cd "../$root"
      git worktree remove "$cwd" --force || return 1
      git branch -D "$branch"
    fi
  fi
}

# ── tmux layouts ────────────────────────────────────────────────────────────────────────────────────────
# Create a Tmux Dev Layout with editor, ai, and terminal
# Usage: tdl <c|cx|codex|other_ai> [<second_ai>]
tdl() {
  [[ -z $1 ]] && { echo "Usage: tdl <c|cx|codex|other_ai> [<second_ai>]"; return 1; }
  [[ -z $TMUX ]] && { echo "You must start tmux to use tdl."; return 1; }

  local current_dir="${PWD}"
  local editor_pane ai_pane ai2_pane
  local ai="$1"
  local ai2="$2"

  # Use TMUX_PANE for the pane we're running in (stable even if active window changes)
  editor_pane="$TMUX_PANE"

  # Name the current window after the base directory name
  tmux rename-window -t "$editor_pane" "$(basename "$current_dir")"

  # Split window vertically - top 85%, bottom 15% (target editor pane explicitly)
  tmux split-window -v -p 15 -t "$editor_pane" -c "$current_dir"

  # Split editor pane horizontally - AI on right 30% (capture new pane ID directly)
  ai_pane=$(tmux split-window -h -p 30 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')

  # If second AI provided, split the AI pane vertically
  if [[ -n $ai2 ]]; then
    ai2_pane=$(tmux split-window -v -t "$ai_pane" -c "$current_dir" -P -F '#{pane_id}')
    tmux send-keys -t "$ai2_pane" "$ai2" C-m
  fi

  # Run ai in the right pane
  tmux send-keys -t "$ai_pane" "$ai" C-m

  # Run nvim in the left pane
  tmux send-keys -t "$editor_pane" "$EDITOR ." C-m

  # Select the nvim pane for focus (Omarchy's original named an unset variable here)
  tmux select-pane -t "$editor_pane"
}

# Create a Tmux Dev Square layout with editor, diff watch, terminal, and opencode
# Usage: tds
tds() {
  [[ -n $1 ]] && { echo "Usage: tds"; return 1; }
  [[ -z $TMUX ]] && { echo "You must start tmux to use tds."; return 1; }

  local current_dir="${PWD}"
  local editor_pane diff_pane terminal_pane opencode_pane

  editor_pane="$TMUX_PANE"

  tmux rename-window -t "$editor_pane" "$(basename "$current_dir")"

  terminal_pane=$(tmux split-window -v -p 50 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')
  diff_pane=$(tmux split-window -h -p 50 -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')
  opencode_pane=$(tmux split-window -h -p 50 -t "$terminal_pane" -c "$current_dir" -P -F '#{pane_id}')

  tmux send-keys -t "$editor_pane" -l "nvim ."
  tmux send-keys -t "$editor_pane" C-m
  tmux send-keys -t "$diff_pane" -l "hunk diff --watch"
  tmux send-keys -t "$diff_pane" C-m
  tmux send-keys -t "$opencode_pane" -l "opencode"
  tmux send-keys -t "$opencode_pane" C-m

  tmux select-pane -t "$editor_pane"
}

# Create multiple tdl windows with one per subdirectory in the current directory
# Usage: tdlm <c|cx|codex|other_ai> [<second_ai>]
tdlm() {
  [ -n "${ZSH_VERSION:-}" ] && setopt local_options ksh_arrays null_glob
  [[ -z $1 ]] && { echo "Usage: tdlm <c|cx|codex|other_ai> [<second_ai>]"; return 1; }
  [[ -z $TMUX ]] && { echo "You must start tmux to use tdlm."; return 1; }

  local ai="$1"
  local ai2="$2"
  local base_dir="$PWD"
  local first=true

  # Rename the session to the current directory name (replace dots/colons which tmux disallows)
  tmux rename-session "$(basename "$base_dir" | tr '.:' '--')"

  for dir in "$base_dir"/*/; do
    [[ -d $dir ]] || continue
    local dirpath="${dir%/}"

    if $first; then
      # Reuse the current window for the first project
      tmux send-keys -t "$TMUX_PANE" "cd '$dirpath' && tdl $ai $ai2" C-m
      first=false
    else
      local pane_id=$(tmux new-window -c "$dirpath" -P -F '#{pane_id}')
      tmux send-keys -t "$pane_id" "tdl $ai $ai2" C-m
    fi
  done
}

# Create a multi-pane swarm layout with the same command started in each pane (great for AI)
# Usage: tsl <pane_count> <command>
tsl() {
  [ -n "${ZSH_VERSION:-}" ] && setopt local_options ksh_arrays null_glob
  [[ -z $1 || -z $2 ]] && { echo "Usage: tsl <pane_count> <command>"; return 1; }
  [[ -z $TMUX ]] && { echo "You must start tmux to use tsl."; return 1; }

  local count="$1"
  local cmd="$2"
  local current_dir="${PWD}"
  local -a panes

  tmux rename-window -t "$TMUX_PANE" "$(basename "$current_dir")"

  panes+=("$TMUX_PANE")

  while (( ${#panes[@]} < count )); do
    local new_pane
    local split_target="${panes[-1]}"
    new_pane=$(tmux split-window -h -t "$split_target" -c "$current_dir" -P -F '#{pane_id}')
    panes+=("$new_pane")
    tmux select-layout -t "${panes[0]}" tiled
  done

  for pane in "${panes[@]}"; do
    tmux send-keys -t "$pane" "$cmd" C-m
  done

  tmux select-pane -t "${panes[0]}"
}

# ── herdr layouts ───────────────────────────────────────────────────────────────────────────────────────
# Echo a split ratio as a float
# Usage: _herdr_ratio <numerator> <denominator>
_herdr_ratio() {
  awk -v a="$1" -v b="$2" 'BEGIN { printf "%.4f", a / b }'
}

# Split a herdr pane and echo the id of the new pane
# Usage: _herdr_split <pane_id> <right|down> <ratio> <cwd>
_herdr_split() {
  herdr pane split "$1" --direction "$2" --ratio "$3" --cwd "$4" --no-focus |
    jq -r '.result.pane.pane_id'
}

# Create a Herdr Dev Layout with editor, ai, and terminal
# Usage: hdl <c|cx|codex|other_ai> [<second_ai>]
hdl() {
  [[ -z $1 ]] && { echo "Usage: hdl <c|cx|codex|other_ai> [<second_ai>]"; return 1; }
  [[ -z $HERDR_PANE_ID ]] && { echo "You must start herdr to use hdl."; return 1; }

  local current_dir="${PWD}"
  local editor_pane ai_pane ai2_pane
  local ai="$1"
  local ai2="${2:-}"

  # Use HERDR_PANE_ID for the pane we're running in (stable even if focus moves)
  editor_pane="$HERDR_PANE_ID"

  # Name the current tab after the base directory name
  herdr tab rename "$HERDR_TAB_ID" "$(basename "$current_dir")" >/dev/null

  # Split tab vertically - top 85%, bottom 15%
  _herdr_split "$editor_pane" down 0.85 "$current_dir" >/dev/null

  # Split editor pane horizontally - AI on right 30%
  ai_pane=$(_herdr_split "$editor_pane" right 0.7 "$current_dir")

  # If second AI provided, split the AI pane vertically
  if [[ -n $ai2 ]]; then
    ai2_pane=$(_herdr_split "$ai_pane" down 0.5 "$current_dir")
    herdr pane run "$ai2_pane" "$ai2" >/dev/null
  fi

  # Run ai in the right pane
  herdr pane run "$ai_pane" "$ai" >/dev/null

  # Run nvim in the left pane
  herdr pane run "$editor_pane" "$EDITOR ." >/dev/null
}

# Create a Herdr Dev Square layout with editor, diff watch, terminal, and opencode
# Usage: hds
hds() {
  [[ -n $1 ]] && { echo "Usage: hds"; return 1; }
  [[ -z $HERDR_PANE_ID ]] && { echo "You must start herdr to use hds."; return 1; }

  local current_dir="${PWD}"
  local editor_pane diff_pane terminal_pane opencode_pane

  editor_pane="$HERDR_PANE_ID"

  herdr tab rename "$HERDR_TAB_ID" "$(basename "$current_dir")" >/dev/null

  terminal_pane=$(_herdr_split "$editor_pane" down 0.5 "$current_dir")
  diff_pane=$(_herdr_split "$editor_pane" right 0.5 "$current_dir")
  opencode_pane=$(_herdr_split "$terminal_pane" right 0.5 "$current_dir")

  herdr pane run "$editor_pane" "nvim ." >/dev/null
  herdr pane run "$diff_pane" "hunk diff --watch" >/dev/null
  herdr pane run "$opencode_pane" "opencode" >/dev/null
}

# Create multiple hdl tabs with one per subdirectory in the current directory
# Usage: hdlm <c|cx|codex|other_ai> [<second_ai>]
hdlm() {
  [ -n "${ZSH_VERSION:-}" ] && setopt local_options ksh_arrays null_glob
  [[ -z $1 ]] && { echo "Usage: hdlm <c|cx|codex|other_ai> [<second_ai>]"; return 1; }
  [[ -z $HERDR_PANE_ID ]] && { echo "You must start herdr to use hdlm."; return 1; }

  local ai="$1"
  local ai2="${2:-}"
  local base_dir="$PWD"
  local first=true
  local hdl_command

  # Rename the workspace to the current directory name
  herdr workspace rename "$HERDR_WORKSPACE_ID" "$(basename "$base_dir")" >/dev/null

  for dir in "$base_dir"/*/; do
    [[ -d $dir ]] || continue
    local dirpath="${dir%/}"

    hdl_command="hdl $(_dotfiles_quote "$ai")"
    [[ -n $ai2 ]] && hdl_command="$hdl_command $(_dotfiles_quote "$ai2")"

    if $first; then
      # Reuse the current tab for the first project
      hdl_command="cd $(_dotfiles_quote "$dirpath") && $hdl_command"
      herdr pane run "$HERDR_PANE_ID" "$hdl_command" >/dev/null
      first=false
    else
      local pane_id
      pane_id=$(herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$dirpath" --no-focus |
        jq -r '.result.root_pane.pane_id')
      herdr pane run "$pane_id" "$hdl_command" >/dev/null
    fi
  done
}

# Create a multi-pane swarm layout with the same command started in each pane (great for AI)
# Usage: hsl <pane_count> <command>
hsl() {
  [ -n "${ZSH_VERSION:-}" ] && setopt local_options ksh_arrays null_glob
  [[ -z $1 || -z $2 ]] && { echo "Usage: hsl <pane_count> <command>"; return 1; }
  [[ -z $HERDR_PANE_ID ]] && { echo "You must start herdr to use hsl."; return 1; }

  local count="$1"
  local cmd="$2"
  local current_dir="${PWD}"
  local -a columns panes

  herdr tab rename "$HERDR_TAB_ID" "$(basename "$current_dir")" >/dev/null

  # Tile into a grid: ceil(sqrt(count)) columns, rows spread across them
  local cols=1
  while (( cols * cols < count )); do ((cols++)); done

  # Even columns come from splitting the rightmost one off at 1/(n-k+1) each time,
  # which keeps the array in left-to-right order
  columns=("$HERDR_PANE_ID")
  local k
  for (( k = 1; k < cols; k++ )); do
    columns+=("$(_herdr_split "${columns[-1]}" right "$(_herdr_ratio 1 $((cols - k + 1)))" "$current_dir")")
  done

  # Split each column into its share of rows, again evenly and top-to-bottom
  local col index rows j last
  for (( index = 0; index < cols; index++ )); do
    col="${columns[index]}"
    rows=$(( count / cols ))
    (( index < count % cols )) && (( rows++ ))
    panes+=("$col")
    last="$col"
    for (( j = 1; j < rows; j++ )); do
      last=$(_herdr_split "$last" down "$(_herdr_ratio 1 $((rows - j + 1)))" "$current_dir")
      panes+=("$last")
    done
  done

  local pane
  for pane in "${panes[@]}"; do
    herdr pane run "$pane" "$cmd" >/dev/null
  done
}

# ── ssh: clean up the terminal and reconnect when a connection drops ─────────────────────────────────────
# A remote tmux, herdr, or editor arms terminal modes over the SSH pipe (mouse tracking, focus reporting,
# the alternate screen) that only it can disarm. If the connection dies instead of exiting cleanly, those
# modes stay armed on the local terminal, and every mouse move floods the prompt with escape junk.
ssh() {
  local rc started

  started=$SECONDS
  command ssh "$@"
  rc=$?

  [[ -t 1 ]] || return $rc
  _ssh_disarm

  # Reconnect only when an interactive session drops: ssh exits 255 for
  # transport failures, but a fast 255 with no established session is a
  # connect/auth failure, a remote command's own 255 passes through
  # indistinguishably and must not replay its side effects, and redirected
  # stdin would feed the remaining piped input to a fresh remote shell.
  if (( rc != 255 )) || [[ ! -t 0 ]] || ! _ssh_interactive "$@" ||
    (( SECONDS - started < 30 )); then
    return $rc
  fi

  # Retry in a subshell: Ctrl-C reaches the whole foreground process group,
  # so it cancels both the in-flight attempt and the loop itself. Keep
  # retrying fast failures, since a rebooting server refuses connections too.
  (
    while true; do
      echo "Connection lost. Reconnecting (Ctrl-C to stop)..."
      sleep 2
      command ssh "$@"
      rc=$?
      _ssh_disarm
      (( rc != 255 )) && exit $rc
    done
  )
}

# Disarm mouse tracking (1000/1002/1003, 1006 encoding), focus reporting
# (1004), and the alternate screen (1049), and show the cursor again.
_ssh_disarm() {
  printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l\e[?1049l\e[?25h'
}

# True for an interactive session: a destination and no remote command. The
# letters are the ssh(1) options that consume a value, so their arguments are
# not mistaken for the destination.
_ssh_interactive() {
  local value_opts="BbcDEeFIiJLlmOoPpQRSWw"
  local all_args=("$@") arg letters i dest="" opts_done=""

  while (($#)); do
    arg="$1"
    shift

    if [[ -z $opts_done && $arg == "--" ]]; then
      opts_done=1
    elif [[ -z $opts_done && $arg == -?* ]]; then
      letters="${arg#-}"
      for ((i = 0; i < ${#letters}; i++)); do
        if [[ $value_opts == *"${letters:$i:1}"* ]]; then
          # The value is glued to the letter (-p2222) unless the letter ends
          # the argument, in which case it consumes the next one (-p 2222).
          (( i == ${#letters} - 1 )) && shift
          break
        fi
      done
    elif [[ -z $dest ]]; then
      dest="$arg"
    else
      return 1
    fi
  done

  [[ -n $dest ]] || return 1

  # A RemoteCommand from ssh_config or -o replays on reconnect just like a
  # positional command; ssh -G resolves the effective configuration for this
  # exact invocation without connecting. Fail closed when it cannot resolve,
  # since an undetected RemoteCommand must not replay. The explicit "none"
  # cancels a configured command, and some versions emit it when unset.
  local resolved
  resolved=$(command ssh -G "${all_args[@]}" 2>/dev/null) || return 1
  ! grep -i '^remotecommand ' <<<"$resolved" | grep -qvi '^remotecommand none$'
}

# SSH port forwarding: fip <host> <port...> forwards, dip <port...> stops, lip lists.
fip() {
  (( $# < 2 )) && echo "Usage: fip <host> <port1> [port2] ..." && return 1
  local host="$1"
  shift
  for port in "$@"; do
    ssh -f -N -L "${port}:localhost:${port}" "$host" && echo "Forwarding localhost:$port -> $host:$port"
  done
}

dip() {
  (( $# == 0 )) && echo "Usage: dip <port1> [port2] ..." && return 1
  for port in "$@"; do
    pkill -f "ssh.*-L ${port}:localhost:${port}" && echo "Stopped forwarding port $port" || echo "No forwarding on port $port"
  done
}

lip() {
  pgrep -af "ssh.*-L [0-9]+:localhost:[0-9]+" || echo "No active forwards"
}

# ── archives ────────────────────────────────────────────────────────────────────────────────────────────
compress() { tar -czf "${1%/}.tar.gz" "${1%/}"; }
alias decompress="tar -xzf"

# ── rsync-on-change watchers (Linux only: need setsid, inotifywait and procps' pgrep -a) ──────────────────
# rsw starts one in the background, lsw lists, dsw stops
if [ "$(uname -s)" = Linux ]; then
  rsw() {
    (( $# != 2 )) && echo "Usage: rsw <source> <destination>" && return 1
    local src="${1%/}" dest="$2"
    # Reuse one SSH connection per login, so 1Password only prompts once.
    local sockets="${XDG_RUNTIME_DIR:-$HOME/.ssh/sockets}"
    mkdir -p "$sockets"
    local rsh="ssh -o ControlMaster=auto -o ControlPath=$sockets/rsw-%r@%h:%p -o ControlPersist=yes"
    setsid --fork env RSYNC_RSH="$rsh" bash -c 'rsync -a "$1/" "$2"; while inotifywait -r -q -e modify,create,delete,move "$1"; do rsync -a "$1/" "$2"; done' rsw-watch "$src" "$dest" >/dev/null 2>&1
    echo "Watching $src -> $dest"
  }

  lsw() {
    local pid cmd rest found=0
    while read -r pid cmd; do
      rest="${cmd##*rsw-watch }"
      echo "$pid: ${rest% *} -> ${rest##* }"
      found=1
    done < <(pgrep -af 'rsw-watch ')
    (( found )) || echo "No active watches"
  }

  dsw() {
    local pid found=0
    for pid in $(pgrep -f 'rsw-watch '); do
      kill -- -"$pid" 2>/dev/null && echo "Stopped watch (pid $pid)" && found=1
    done
    (( found )) || echo "No active watches"
  }
fi
