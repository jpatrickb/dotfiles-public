#!/bin/bash
# Runs inside the container after apply.sh. Prints PASS/FAIL per check.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/.fzf/bin:$HOME/.atuin/bin:$HOME/google-cloud-sdk/bin:/usr/local/bin:$PATH"   # same extras the shell config adds
fail=0
# machine class as chezmoi detected it: the Arch family runs bash, Ubuntu runs zsh
FAMILY=$(chezmoi --source /src data --format json 2>/dev/null | jq -r '.family // empty')
ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=1; }
chk() { local out; if out=$( ( eval "$2" ) 2>&1 ); then ok "$1"; else bad "$1"; [ -n "$out" ] && printf "%s\n" "$out" | head -8 | sed "s/^/          /"; fi; }   # subshell: a check may call exit

echo; echo "=== tools installed ==="
chk "nvim >= 0.12"      "nvim --version | head -1 | grep -qE 'v(0\.(1[2-9]|[2-9][0-9])|[1-9])'"
for t in go rustc cargo rustfmt terraform tmux starship zoxide fzf eza bat rg fd tree-sitter delta mise uv fastfetch tldr mdcat gh jq lazygit btop atuin direnv; do
  chk "$t on PATH" "command -v $t"
done
[ "$FAMILY" = debian ] && chk "zsh on PATH (Ubuntu runs zsh)" "command -v zsh"

echo; echo "=== chezmoi state ==="
# git must page through delta in a real terminal (this broke fresh installs once: missing delta = fatal)
chk "git log/diff work in a tty (delta pager)" 'cd $(mktemp -d) && git init -q . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m x && printf a > f && git add f && git -c user.name=t -c user.email=t@t commit -q -m y && script -qec "git log -2 --oneline" /dev/null >/dev/null && script -qec "git diff HEAD~1" /dev/null >/dev/null'
chk "uv works" 'uv --version'
if [ "${AWS_CLI:-true}" = true ]; then chk "aws on PATH + runs" 'aws --version'
else chk "aws skipped when declined" '! command -v aws'; fi
if [ "${GCP_CLI:-true}" = true ]; then chk "gcloud on PATH + runs" 'gcloud --version | head -1'
else chk "gcloud skipped when declined" '! command -v gcloud'; fi
chk "mason python tools install without pip package" '! dpkg -s python3-pip >/dev/null 2>&1'
chk "~/.gitconfig.local auto-created with placeholders" "grep -q 'FILL ME IN' ~/.gitconfig.local"
chk "machine class detected (family is arch or debian, env is native)" "[ \"$FAMILY\" = arch ] || [ \"$FAMILY\" = debian ]; [ \"\$(chezmoi --source /src data --format json | jq -r .env)\" = native ]"
chk "Neovim theme file is a regular file here (the synced copy, not Omarchy's symlink)" "[ -f ~/.config/nvim/lua/plugins/theme.lua ] && [ ! -L ~/.config/nvim/lua/plugins/theme.lua ]"
chk "Omarchy-only files are not installed" "[ ! -e ~/.config/omarchy ] && [ ! -e ~/.config/nvim/lua/config/remote_clipboard.lua ] && [ ! -e ~/.config/foot ]"
chk "old kickstart plugin files are gone" "[ ! -e ~/.config/nvim/lua/plugins/lsp.lua ] && [ ! -e ~/.config/nvim/lua/plugins/colorscheme.lua ]"
chk "chezmoi status clean (only R scripts)" 's=$(chezmoi --source /src status | grep -v "^ R"); [ -z "$s" ] || { echo "$s"; false; }'

echo; echo "=== shell + tmux start without errors ==="
if [ "$FAMILY" = arch ]; then
  chk "bash is the login shell setup: ~/.bashrc has the dotfiles block, no .zshrc" 'grep -q "dotfiles" ~/.bashrc && [ ! -e ~/.zshrc ]'
  chk "AUR helper yay is installed (built from the AUR on a fresh Arch)" 'command -v yay'
  chk "ble.sh 0.4 is installed (blesh-git, through yay)" 'pacman -Q blesh-git'
  chk "bash interactive startup, no errors" '[ -z "$(bash -ic exit 2>&1 >/dev/null | grep -i -E "error|not found|no such|unknown|syntax")" ]'
else
  chk "Ubuntu's global compinit is skipped (skip_global_compinit set in ~/.zshenv)" '[ "$(zsh -c "print \$skip_global_compinit")" = 1 ]'
  chk "zsh interactive startup, no errors" '[ -z "$(zsh -ic exit 2>&1 >/dev/null | grep -i -E "error|not found|no such|unknown")" ]'
  chk "no ~/.bashrc block on a zsh machine" '! grep -q "dotfiles (chezmoi)" ~/.bashrc 2>/dev/null'
fi
chk "tmux.conf loads, no errors" 'tmux -L t -f ~/.config/tmux/tmux.conf new-session -d && [ -z "$(tmux -L t show-messages | grep -i -E "invalid|unknown|error")" ]; r=$?; tmux -L t kill-server 2>/dev/null; exit $r'
chk "git accepts merge.conflictstyle" 'git config --global merge.conflictstyle && git -c core.pager=cat log -1 >/dev/null 2>&1 || git config --global merge.conflictstyle'

echo; echo "=== neovim: plugins from the lock file, parsers, Mason tools (slow) ==="
nvim --headless "+Lazy! restore" +qa 2>&1 | tail -5
chk "lazy restore left no failed plugins" '[ -z "$(nvim --headless "+lua for n,p in pairs(require(\"lazy\").plugins()) do if not p._.installed then print(\"MISSING \"..p.name) end end" +qa 2>&1 | grep MISSING)" ]'
chk "plugins sit at the lock-file commits" 'cd ~/.config/nvim && python3 - <<PY
import json,subprocess,os
lock=json.load(open("lazy-lock.json")); d=os.path.expanduser("~/.local/share/nvim/lazy"); bad=[]
for n,e in lock.items():
    p=os.path.join(d,n)
    if os.path.isdir(p) and subprocess.run(["git","-C",p,"rev-parse","HEAD"],capture_output=True,text=True).stdout.strip()!=e["commit"]: bad.append(n)
assert not bad, bad
PY'
timeout 700 nvim --headless "+lua require('nvim-treesitter').install({'lua','markdown','markdown_inline','go','rust','hcl','terraform','python'}):wait(600000)" +qa 2>&1 | tail -3
# every Mason package the config asks for (LazyVim's lists plus ours); prints MASON ok/FAILED per package
mason_out=$(timeout 1700 nvim --headless "+luafile /src/.test/mason-install.lua" +qa 2>&1 | grep '^MASON')
echo "$mason_out" | sed 's/^/  /'
M="$HOME/.local/share/nvim/mason/bin"
for t in stylua prettier gofumpt goimports golangci-lint checkmake tflint ruff gopls pyright vtsls marksman harper-ls markdownlint-cli2 sqlfluff terraform-ls lua-language-server; do
  chk "mason: $t" "[ -e $M/$t ] || echo \"\$mason_out\" | grep -q 'MASON SKIP $t '"   # SKIP = Mason has no build for this CPU
done
chk "mason: no package failed to install" '! echo "$mason_out" | grep -q "MASON FAILED"'

echo; echo "=== formatting end to end (conform; python and rust format through their language servers in an editor, so their tools are run directly) ==="
fmt() { nvim --headless "$1" "+lua require('conform').format({async=false,timeout_ms=15000})" +wq 2>&1 | tail -2; }
cd "$(mktemp -d)"
printf 'local   x   =    1\n'                    > a.lua; fmt a.lua; chk "format lua (stylua)"      "grep -q '^local x = 1$' a.lua"
printf '#   Title\n\n*  item\n'                   > a.md;  fmt a.md;  chk "format markdown (prettier)" "grep -q '^# Title$' a.md && grep -q '^- item$' a.md"
printf 'package main\nfunc main(){}\n'            > a.go;  fmt a.go;  chk "format go (gofumpt)"       "grep -q 'func main() {}' a.go"
printf 'resource "a" "b" {\nx=1\n}\n'             > a.tf;  fmt a.tf;  chk "format terraform (fmt)"    "grep -q 'x = 1' a.tf"
printf 'x=1\nimport os\n'                         > a.py;  "$M/ruff" format a.py >/dev/null 2>&1; chk "format python (ruff)" "grep -q '^x = 1$' a.py"
printf 'fn main(){let x=1;}\n'                    > a.rs;  rustfmt a.rs 2>/dev/null; chk "format rust (rustfmt)" "grep -q 'fn main() {' a.rs"

echo; [ $fail -eq 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $fail
