#!/bin/bash
# Claude Code status line: model name + context used % + workspace name + effort level

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
workspace=$(echo "$input" | jq -r '(.workspace.project_dir // .workspace.current_dir) // empty')
[ -n "$workspace" ] && workspace=$(basename "$workspace")
effort=$(echo "$input" | jq -r '.effort.level // empty')

out="\033[2m${model}\033[0m"

if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")
  [ "$used_int" -gt 100 ] && used_int=100
  [ "$used_int" -lt 0 ] && used_int=0

  # Color based on usage level
  if [ "$used_int" -ge 80 ]; then
    color="\033[31m"   # red
  elif [ "$used_int" -ge 50 ]; then
    color="\033[33m"   # yellow
  else
    color="\033[32m"   # green
  fi

  out="${out} \033[2m|\033[0m ${color}${used_int}%\033[0m"
fi

[ -n "$workspace" ] && out="${out} \033[2m|\033[0m ${workspace}"
[ -n "$effort" ] && out="${out} \033[2m|\033[0m ${effort}"

printf "%b\n" "$out"
