#!/bin/bash
# [custom] Tools where apt's packaged version is too stale for this config
# (or apt doesn't ship it at all), installed from upstream instead. No-ops
# instantly anywhere apt isn't the package manager (this Mac already has all
# of these via Homebrew).
set -euo pipefail

command -v apt-get >/dev/null 2>&1 || command -v pacman >/dev/null 2>&1 || exit 0

# Omarchy ships current versions of these through pacman, and its language toolchains (go, rust, terraform)
# are managed with mise rather than system-wide tarballs in /usr/local. Skip everything here on Omarchy.
if [ -d /usr/share/omarchy ]; then
  echo "==> Omarchy detected: skipping upstream tool installers (pacman and mise provide these)."
  exit 0
fi

export PATH="$HOME/.local/bin:$PATH"

# Keep installer scratch files out of /tmp: some upstream installers (zoxide,
# direnv) leave temp files behind.
UPSTREAM_TMP="$(mktemp -d)"; export TMPDIR="$UPSTREAM_TMP"
trap 'rm -rf "$UPSTREAM_TMP"' EXIT

# Neovim: apt's version is too old for lazy.nvim + this plugin set.
if ! command -v nvim >/dev/null 2>&1 || ! nvim --version | head -1 | grep -qE 'v(0\.(1[2-9]|[2-9][0-9])|[1-9])'; then
  case "$(uname -m)" in
    x86_64) NVIM_ARCH=x86_64 ;;
    aarch64|arm64) NVIM_ARCH=arm64 ;;
    *) echo "  (unrecognized architecture $(uname -m) -- skipping Neovim)"; NVIM_ARCH="" ;;
  esac
  if [ -n "$NVIM_ARCH" ]; then
    echo "==> Installing current Neovim from the official release tarball..."
    echo "    (if this URL 404s, check https://github.com/neovim/neovim/releases"
    echo "     for the current asset name -- it has changed before)"
    curl -fLo /tmp/nvim.tar.gz \
      "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz"
    sudo rm -rf "/opt/nvim-linux-${NVIM_ARCH}"
    sudo tar -C /opt -xzf /tmp/nvim.tar.gz
    sudo ln -sf "/opt/nvim-linux-${NVIM_ARCH}/bin/nvim" /usr/local/bin/nvim
    rm -f /tmp/nvim.tar.gz
  fi
fi

# Go: mason installs sqls, gopls, goimports, gofumpt etc. with `go install`, so
# the toolchain must exist before nvim's first launch. apt's golang-go is too
# old for current versions of those tools, so use the official tarball.
if ! command -v go >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64) GO_ARCH=amd64 ;;
    aarch64|arm64) GO_ARCH=arm64 ;;
    *) echo "  (unrecognized architecture $(uname -m) -- skipping Go; Mason's Go-based tools will fail to install)"; GO_ARCH="" ;;
  esac
  if [ -n "$GO_ARCH" ]; then
    echo "==> Installing Go from go.dev..."
    GO_VER="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1)"
    curl -fLo /tmp/go.tar.gz "https://go.dev/dl/${GO_VER}.linux-${GO_ARCH}.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz
    sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go
    sudo ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
    rm -f /tmp/go.tar.gz
  fi
fi

# Node + npm: Mason's npm-based tools (prettier, ...) and Kilo Code need them.
# Official tarball into ~/.local/share/node (apt's npm pulls in ~500 packages).
# Arch installs them via pacman, so this is skipped there.
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64)        NODE_ARCH=x64 ;;
    aarch64|arm64) NODE_ARCH=arm64 ;;
    *) NODE_ARCH="" ;;
  esac
  if [ -n "$NODE_ARCH" ]; then
    echo "==> Installing Node.js LTS from nodejs.org..."
    NODE_VER="$(curl -fsSL https://nodejs.org/dist/index.json | jq -r '[.[] | select(.lts != false)][0].version')"
    curl -fLo /tmp/node.tar.xz "https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-${NODE_ARCH}.tar.xz"
    rm -rf "$HOME/.local/share/node"
    mkdir -p "$HOME/.local/share/node" "$HOME/.local/bin"
    tar -C "$HOME/.local/share/node" --strip-components=1 -xJf /tmp/node.tar.xz
    for b in node npm npx corepack; do ln -sf "$HOME/.local/share/node/bin/$b" "$HOME/.local/bin/$b"; done
    rm -f /tmp/node.tar.xz
  fi
fi

# Rust: per-user via rustup (no sudo). Minimal profile (no docs: ~1 GB smaller) plus
# rustfmt (conform.nvim's formatter) and clippy. .zshrc sources
# ~/.cargo/env when it exists.
if ! command -v rustc >/dev/null 2>&1 && [ ! -x "$HOME/.cargo/bin/rustc" ]; then
  echo "==> Installing Rust via rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal -c rustfmt -c clippy
fi

# Terraform: per-user binary from HashiCorp's release zip (their apt repo lags
# new Ubuntu releases), into ~/.local/bin.
if ! command -v terraform >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64) TF_ARCH=amd64 ;;
    aarch64|arm64) TF_ARCH=arm64 ;;
    *) echo "  (unrecognized architecture $(uname -m) -- skipping Terraform)"; TF_ARCH="" ;;
  esac
  if [ -n "$TF_ARCH" ]; then
    echo "==> Installing Terraform..."
    TF_VER="$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | sed -n 's/.*"current_version":"\([^"]*\)".*/\1/p')"
    curl -fLo /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${TF_VER}/terraform_${TF_VER}_linux_${TF_ARCH}.zip"
    mkdir -p "$HOME/.local/bin"
    unzip -o -q /tmp/terraform.zip terraform -d "$HOME/.local/bin"
    rm -f /tmp/terraform.zip
  fi
fi

# starship / zoxide / direnv / atuin: official installers (apt lags).
command -v starship >/dev/null 2>&1 || curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
command -v zoxide    >/dev/null 2>&1 || curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
rm -rf /tmp/zoxide_* 2>/dev/null || true   # its installer ignores TMPDIR and leaves this behind
command -v direnv    >/dev/null 2>&1 || curl -sfL https://direnv.net/install.sh | bash
command -v atuin     >/dev/null 2>&1 || bash -c "$(curl --proto '=https' --tlsv1.2 -sSf https://setup.atuin.sh)"

# fzf: install a current copy via git rather than relying on apt's (often
# stale) package -- the `fzf --zsh` integration in .zshrc needs fzf >= 0.48.
# Skipped when a new enough fzf is already installed (e.g. Arch's package).
fzf_ok() { command -v fzf >/dev/null 2>&1 && [ "$(printf '%s\n0.48\n' "$(fzf --version | cut -d' ' -f1)" | sort -V | head -1)" = "0.48" ]; }
if [ ! -d "$HOME/.fzf" ] && ! fzf_ok; then
  echo "==> Installing fzf..."
  git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  "$HOME/.fzf/install" --bin --no-update-rc --no-key-bindings --no-completion
fi

# tree-sitter CLI: nvim-treesitter's `main` branch (used on Neovim 0.12+,
# see lua/plugins/treesitter.lua) shells out to `tree-sitter build` to
# compile parsers -- not apt-packaged, and this Mac already has it via
# Homebrew, which is why this was missed until the first real fresh-machine
# test surfaced "ENOENT ... 'tree-sitter'" on every parser install.
if ! command -v tree-sitter >/dev/null 2>&1; then
  echo "==> Installing tree-sitter CLI..."
  echo "    (if this URL 404s, check https://github.com/tree-sitter/tree-sitter/releases"
  echo "     for the current asset name -- verified live at write time, but can change)"
  TS_ARCH="$(uname -m)"
  case "$TS_ARCH" in
    x86_64)  TS_TARGET="linux-x64" ;;
    aarch64) TS_TARGET="linux-arm64" ;;
    *) echo "  (unrecognized architecture $TS_ARCH -- skipping tree-sitter CLI, parser installs will fail until this is added manually)"; TS_TARGET="" ;;
  esac
  if [ -n "$TS_TARGET" ]; then
    mkdir -p "$HOME/.local/bin"
    curl -fLo /tmp/tree-sitter.gz "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-${TS_TARGET}.gz"
    gunzip -f /tmp/tree-sitter.gz
    mv /tmp/tree-sitter "$HOME/.local/bin/tree-sitter"
    chmod +x "$HOME/.local/bin/tree-sitter"
  fi
fi

# eza (modern ls replacement, colored by the terminal's own palette):
# never made it into the original apt package list at all, missed until the
# third machine's real bootstrap surfaced it missing entirely.
if ! command -v eza >/dev/null 2>&1; then
  echo "==> Installing eza..."
  echo "    (if this URL 404s, check https://github.com/eza-community/eza/releases"
  echo "     for the current asset name -- verified live at write time, but can change)"
  EZA_ARCH="$(uname -m)"
  case "$EZA_ARCH" in
    x86_64)  EZA_TARGET="x86_64-unknown-linux-gnu" ;;
    aarch64) EZA_TARGET="aarch64-unknown-linux-gnu" ;;
    *) echo "  (unrecognized architecture $EZA_ARCH -- skipping eza)"; EZA_TARGET="" ;;
  esac
  if [ -n "$EZA_TARGET" ]; then
    mkdir -p "$HOME/.local/bin"
    curl -fLo /tmp/eza.tar.gz "https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_TARGET}.tar.gz"
    # No member name specified -- the archive contains only this one binary
    # (at "./eza", not plain "eza", which is what broke this the first
    # time: naming an exact member is brittle to that kind of prefix).
    tar -C "$HOME/.local/bin" -xzf /tmp/eza.tar.gz
    chmod +x "$HOME/.local/bin/eza"
    rm -f /tmp/eza.tar.gz
  fi
fi

# tlrc (tldr client -- simplified, example-based man pages). Asset filenames
# embed the version number, so this pins one rather than using a "latest"
# URL, same as tlrc/delta above -- bump the version here periodically.
TLRC_VERSION="1.13.1"
if ! command -v tldr >/dev/null 2>&1; then
  echo "==> Installing tlrc v$TLRC_VERSION (tldr client)..."
  TLRC_ARCH="$(uname -m)"
  case "$TLRC_ARCH" in
    x86_64)  TLRC_TARGET="x86_64-unknown-linux-gnu" ;;
    aarch64) TLRC_TARGET="aarch64-unknown-linux-gnu" ;;
    *) echo "  (unrecognized architecture $TLRC_ARCH -- skipping tlrc)"; TLRC_TARGET="" ;;
  esac
  if [ -n "$TLRC_TARGET" ]; then
    mkdir -p "$HOME/.local/bin"
    curl -fLo /tmp/tlrc.tar.gz "https://github.com/tldr-pages/tlrc/releases/download/v${TLRC_VERSION}/tlrc-v${TLRC_VERSION}-${TLRC_TARGET}.tar.gz"
    mkdir -p /tmp/tlrc-extract
    # Extract just the binary, not the README/LICENSE/completions also in
    # the archive -- verified the exact member name (plain "tldr", no
    # nested dir or "./" prefix) before writing this.
    tar -C /tmp/tlrc-extract -xzf /tmp/tlrc.tar.gz tldr
    cp /tmp/tlrc-extract/tldr "$HOME/.local/bin/tldr"
    chmod +x "$HOME/.local/bin/tldr"
    rm -rf /tmp/tlrc.tar.gz /tmp/tlrc-extract
  fi
fi

# mdcat (prints markdown to the terminal with real formatting). Homebrew's
# formula (and thus this pinned version) tracks the BIRSAx2/mdcat fork, not
# the original swsnr/mdcat -- same kind of fork situation already hit with
# fast-syntax-highlighting, so pin explicitly rather than assume. Asset
# filenames embed the version, so pinned like tlrc/delta above.
MDCAT_VERSION="2.17.0"
if ! command -v mdcat >/dev/null 2>&1; then
  echo "==> Installing mdcat v$MDCAT_VERSION..."
  MDCAT_ARCH="$(uname -m)"
  case "$MDCAT_ARCH" in
    x86_64)  MDCAT_TARGET="x86_64-unknown-linux-gnu" ;;
    aarch64) MDCAT_TARGET="aarch64-unknown-linux-gnu" ;;
    *) echo "  (unrecognized architecture $MDCAT_ARCH -- skipping mdcat)"; MDCAT_TARGET="" ;;
  esac
  if [ -n "$MDCAT_TARGET" ]; then
    mkdir -p "$HOME/.local/bin"
    curl -fLo /tmp/mdcat.tar.gz \
      "https://github.com/BIRSAx2/mdcat/releases/download/mdcat-${MDCAT_VERSION}/mdcat-${MDCAT_VERSION}-${MDCAT_TARGET}.tar.gz"
    mkdir -p /tmp/mdcat-extract
    # The binary sits nested in a versioned subdirectory (unlike eza/tldr's
    # flat archives), so find it by name rather than hardcoding that path --
    # verified the real nested structure by extracting it before writing this.
    tar -C /tmp/mdcat-extract -xzf /tmp/mdcat.tar.gz
    find /tmp/mdcat-extract -maxdepth 2 -name mdcat -type f -exec cp {} "$HOME/.local/bin/mdcat" \;
    chmod +x "$HOME/.local/bin/mdcat"
    rm -rf /tmp/mdcat.tar.gz /tmp/mdcat-extract
  fi
fi

# git-delta: apt has it on newer Ubuntu (run_once_before_01); this covers releases
# that don't. git degrades gracefully without it (see dot_gitconfig.tmpl).
DELTA_VERSION="0.18.2"
if ! command -v delta >/dev/null 2>&1; then
  echo "==> Installing delta v$DELTA_VERSION..."
  case "$(uname -m)" in
    x86_64)  DELTA_TARGET="x86_64-unknown-linux-gnu" ;;
    aarch64) DELTA_TARGET="aarch64-unknown-linux-gnu" ;;
    *) DELTA_TARGET="" ;;
  esac
  if [ -n "$DELTA_TARGET" ]; then
    mkdir -p "$HOME/.local/bin" /tmp/delta-extract
    curl -fLo /tmp/delta.tar.gz "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${DELTA_TARGET}.tar.gz"
    tar -C /tmp/delta-extract -xzf /tmp/delta.tar.gz
    find /tmp/delta-extract -maxdepth 2 -name delta -type f -exec cp {} "$HOME/.local/bin/delta" \;
    chmod +x "$HOME/.local/bin/delta"
    rm -rf /tmp/delta.tar.gz /tmp/delta-extract
  fi
fi

# lazygit: terminal git UI. Not in older Ubuntu/Debian repos (run_once_before_01 tries apt first); Arch and
# Omarchy get it from pacman, Mac from the Brewfile. Pinned like the tools above; the asset name was checked
# against the release listing (lowercase "linux", x86_64 / arm64). The binary is located by name, not by an
# assumed archive path (same approach as delta). NOT yet exercised on a real Ubuntu install: run .test/run.sh.
LAZYGIT_VERSION="0.66.3"
if ! command -v lazygit >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64)        LAZYGIT_ARCH="x86_64" ;;
    aarch64|arm64) LAZYGIT_ARCH="arm64" ;;
    *) LAZYGIT_ARCH="" ;;
  esac
  if [ -n "$LAZYGIT_ARCH" ]; then
    echo "==> Installing lazygit v$LAZYGIT_VERSION..."
    mkdir -p "$HOME/.local/bin" /tmp/lazygit-extract
    if curl -fLo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_linux_${LAZYGIT_ARCH}.tar.gz" \
      && tar -C /tmp/lazygit-extract -xzf /tmp/lazygit.tar.gz; then
      find /tmp/lazygit-extract -maxdepth 2 -name lazygit -type f -exec cp {} "$HOME/.local/bin/lazygit" \;
      chmod +x "$HOME/.local/bin/lazygit"
    else
      echo "  (lazygit download failed -- skipping; install it manually from https://github.com/jesseduffield/lazygit/releases)"
    fi
    rm -rf /tmp/lazygit.tar.gz /tmp/lazygit-extract
  fi
fi

# mise (tool-version manager; .zshrc activates it when present).
command -v mise >/dev/null 2>&1 || curl -sS https://mise.run | sh

# uv: Python tooling (replaces pip/pipx; Mason's Python tools use venv).
command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
