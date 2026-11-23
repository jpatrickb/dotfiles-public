#!/bin/bash
# Test the dotfiles on a fresh Ubuntu 26.04 (or Arch) container, using your WORKING COPY
# (uncommitted changes included). Usage:
#   .test/run.sh           apply + run all checks, exit non-zero on failure
#   .test/run.sh shell     apply, then drop into the container to poke around
#   PLATFORM=linux/amd64 .test/run.sh    run as x86_64 (slower on Apple Silicon)
#   DISTRO=arch .test/run.sh             test on Arch Linux instead (x86_64 only)
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DISTRO=${DISTRO:-ubuntu}
IMG=dotfiles-test${DISTRO:+-$DISTRO}
[ "$DISTRO" = arch ] && PLATFORM=${PLATFORM:-linux/amd64}
PLAT=${PLATFORM:+--platform $PLATFORM}
DF="$SRC/.test/Dockerfile"; [ "$DISTRO" = ubuntu ] || DF="$DF.$DISTRO"
docker build $PLAT -f "$DF" -t "$IMG" "$SRC/.test"
if [ "${1:-}" = shell ]; then
  docker run --rm -it $PLAT -e AWS_CLI=${AWS_CLI:-true} -e GCP_CLI=${GCP_CLI:-true} -v "$SRC:/src:ro" "$IMG" bash -c 'bash /src/.test/apply.sh; exec bash -l'
else
  docker run --rm $PLAT -e AWS_CLI=${AWS_CLI:-true} -e GCP_CLI=${GCP_CLI:-true} -v "$SRC:/src:ro" "$IMG" bash -c 'bash /src/.test/apply.sh && bash /src/.test/check.sh'
fi
