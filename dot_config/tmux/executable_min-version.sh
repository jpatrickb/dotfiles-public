#!/bin/sh
# [custom] Exit 0 if the running tmux is >= MAJOR.MINOR (arg 1), else 1. Lets
# tmux.conf guard options that older tmux (e.g. Ubuntu's apt build) rejects:
#   if-shell '~/.config/tmux/min-version.sh 3.6' { ... }
v=$(tmux -V | sed 's/[^0-9.]//g')   # "tmux 3.6b" -> "3.6"
awk -v v="$v" -v w="$1" 'BEGIN {
  split(v, a, "."); split(w, b, ".")
  exit !((a[1] * 1000 + a[2]) >= (b[1] * 1000 + b[2]))
}'
