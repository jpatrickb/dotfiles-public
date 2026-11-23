#!/bin/sh
# Publish the current tree to the public mirror as ONE history-free commit.
# Private repo stays the source of truth; never touches its history.
# Usage: scripts/publish-public.sh   (run from anywhere; needs gh/git auth)
set -eu
MIRROR="${MIRROR:-git@github.com:jpatrickb/dotfiles-public.git}"
cd "$(chezmoi source-path)"
[ -z "$(git status --porcelain)" ] || { echo "Uncommitted changes; commit first." >&2; exit 1; }
tree=$(git rev-parse 'HEAD^{tree}')
sha=$(git rev-parse --short HEAD)
commit=$(GIT_AUTHOR_NAME=jpatrickb GIT_AUTHOR_EMAIL=142933271+jpatrickb@users.noreply.github.com \
  GIT_COMMITTER_NAME=jpatrickb GIT_COMMITTER_EMAIL=142933271+jpatrickb@users.noreply.github.com \
  git commit-tree "$tree" -m "Snapshot of private dotfiles@$sha")
git push --force "$MIRROR" "$commit:refs/heads/main"
echo "Published $sha to $MIRROR"
