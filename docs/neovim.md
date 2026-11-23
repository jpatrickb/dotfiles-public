# Neovim (LazyVim)

The config is [LazyVim](https://www.lazyvim.org) as Omarchy ships it, plus a personal layer. Everything lives in
`~/.local/share/chezmoi/dot_config/nvim/` and is installed to `~/.config/nvim/` by `chezmoi apply`. Edit it with
`chezmoi edit --apply ~/.config/nvim/<file>` (or edit the source and apply).

## Layout

| File | What it is |
|---|---|
| `lazyvim.json` | which LazyVim **extras** are on (python, typescript, go, rust, terraform, sql, markdown, prettier, eslint, neo-tree, mini-surround, copilot-native). `:LazyExtras` edits it. |
| `lazy-lock.json` | the exact version of every plugin, shared by all machines |
| `lua/config/options.lua` | options (`relativenumber` on, `scrolloff` 10, `exrc`, ...) |
| `lua/config/keymaps.lua` | personal keys: `<leader>sf`, `<leader><leader>`, `<leader>s.`, journal (`<leader>j*`), `<leader>mm`, `<leader>rp` |
| `lua/config/autocmds.lua` | markdown heading jumps (`]1`..`]6`) and scripture `K`, `:make` quickfix, `:GitBlameLine` |
| `lua/plugins/languages.lua` | pyright venv detection, harper-ls, extra Mason tools and linters |
| `lua/plugins/{completion,editor,ui,treesitter,notes,telescope}.lua` | one concern per file |
| `lua/plugins/theme.lua` | the colour scheme (see below) |
| `lua/config/scripture_*.lua` | your scripture linkify and verse picker |
| the Omarchy files | `all-themes.lua`, `lualine-transparent.lua`, `plugin/after/transparency.lua`, ... copied unchanged from Omarchy's skeleton |

## First launch on a new machine

1. `nvim`. lazy.nvim installs every plugin at the commit in `lazy-lock.json`. If anything looks half-installed run
   `:Lazy restore`.
2. Wait for Mason to finish (`:Mason`; language servers and formatters install in the background), then **restart nvim**.
3. Copilot: `:LspCopilotSignIn` once per machine.
4. `:checkhealth` if something misbehaves.

Needs Neovim **0.12 or newer** (the copilot extra requires it) plus `git`, `curl`, `tree-sitter` and a C compiler;
the install scripts provide them.

## Getting around: the cheat sheet

`<leader>` is **Space**. Press it and wait: which-key lists everything available next.

### Files: neo-tree

| Key | Does |
|---|---|
| `<leader>e` | open or close the file tree (project root) |
| `<leader>E` | the same, rooted at the current directory |
| `<leader>ge` | tree of git-changed files |
| `<leader>be` | tree of open buffers |
| `-` | oil: edit the current directory as a buffer (rename, move, delete by editing lines, then `:w`) |

Inside the tree (press `?` there for the full list):

| Key | Does |
|---|---|
| `j` `k` | move |
| `l` or `Enter` | open file / expand folder |
| `h` | collapse folder |
| `a` | **add** a file (end the name with `/` for a folder) |
| `d` | delete |
| `r` | rename |
| `y` `x` `p` | copy, cut, paste (so: `y` on a file, move to a folder, `p`) |
| `c` / `m` | copy / move, asking for the destination |
| `s` / `S` | open in a vertical / horizontal split |
| `H` | show or hide dotfiles |
| `/` | fuzzy-filter the tree |
| `.` | make the folder under the cursor the new root; `Backspace` goes up |
| `P` | preview the file without leaving the tree |
| `Y` | copy the path to the clipboard |
| `R` | refresh |
| `q` | close the tree |
| `<` `>` | switch between the files / buffers / git views |

The tree follows the file you are editing, and `Ctrl-h` / `Ctrl-l` (or `Alt-h` / `Alt-l`) move between the tree and the
editor.

### Buffers: the tab bar at the top

The tabs are **buffers** (open files), not Neovim tab pages. You open a file once and it stays loaded; the tab bar is
just the list.

| Key | Does |
|---|---|
| `Shift-l` / `Shift-h` (or `]b` / `[b`) | next / previous buffer |
| `<leader>,` or `<leader><leader>` | pick a buffer from a list (most recently used first) |
| `<leader>bb` | jump back to the previous buffer |
| `<leader>bj` | pick a buffer by pressing the letter shown on its tab |
| `<leader>bd` | close this buffer (the window stays) |
| `<leader>bo` | close all other buffers |
| `<leader>bp` | pin the buffer (pinned tabs are kept by the bulk-close commands) |
| `<leader>bP` | close all non-pinned buffers |
| `<leader>br` / `<leader>bl` | close the buffers to the right / left |
| `[B` / `]B` | move this tab left / right |

### Search and pickers (snacks)

| Key | Does |
|---|---|
| `<leader>sf`, `<leader>ff`, `<leader><space>` | find files |
| `<leader>sg` | grep the project |
| `<leader>/` | grep (same, LazyVim's spelling) |
| `<leader>s.`, `<leader>fr` | recent files |
| `<leader>sw` | grep the word under the cursor |
| `<leader>sk` | search keymaps; `<leader>sc` commands; `<leader>sr` resume the last search |

### Code

With a language server attached (open a code file and wait a moment; `:LspInfo`): `gd` definition, `gr` references,
`K` hover, `<leader>ca` code action, `<leader>cr` rename. Always: `<leader>cf` format now, `<leader>cd` line diagnostics, `<leader>xx` diagnostics list, `]d` / `[d` next / previous diagnostic.
Format on save is on: `<leader>uf` turns it off and on. Completion: `Ctrl-n` / `Ctrl-p` select, `Ctrl-y` accept,
`Ctrl-space` open, `Ctrl-e` hide.

### Surround and editing

`gsa` add a surrounding (`gsaiw"` wraps the word in quotes), `gsd` delete, `gsr` replace. `s` is flash (jump to any
visible text). `Alt-j` / `Alt-k` move the line or selection. `Alt-h` / `Alt-l` move between windows.

### Yours

`<leader>jl` / `<leader>jL` link scripture references on the line / in the buffer, `<leader>jv` verse search,
`K` on a reference previews it, `<leader>js` journal sync and `<leader>jc` callouts search (only where the journal
exists), `<leader>mm` `:make`, `<leader>rp` run the Python file with uv.

## Tools Mason installs, and what they need

Mason installs language servers, formatters and linters on first use. A few need a language runtime on the machine:

- Node (via mise) for `prettier`, `vtsls`, `eslint-lsp`, `markdownlint-cli2`, `markdown-toc`.
- Go for `gopls`, `gofumpt`, `goimports`, `golangci-lint`.
- Python for `pyright`, `ruff`, `sqlfluff`.
- **`rust-analyzer` is not from Mason**: rustaceanvim uses the one on your `PATH` (`rustup component add rust-analyzer`,
  or the distro package).

`:Mason` shows what is installed and what failed.

## The colour scheme

`lua/plugins/theme.lua` follows Omarchy's theme.

- **On Omarchy** it is Omarchy's own symlink to its current theme, so a theme switch changes Neovim live. chezmoi
  never touches it.
- **Everywhere else** it is a plain file copied from this repo. The Omarchy theme-switch hook regenerates it (see
  [omarchy.md](omarchy.md#theme-sync)); after you commit and push, `chezmoi git -- pull && chezmoi apply` brings the
  new theme to the other machines. There it takes effect the next time Neovim starts.

Do not edit `theme.lua` in the repo by hand: the next Omarchy theme switch overwrites it.

## Updating plugins

Updates are manual and shared:

1. `:Lazy` then `U` (update all) on one machine; try it for a few days.
2. `chezmoi re-add ~/.config/nvim/lazy-lock.json`, commit and push.
3. On the other machines, pull, `chezmoi apply`, then `:Lazy restore`.

lazy.nvim also checks for updates in the background and does not nag; `:Lazy` shows what is outdated.

## Things that differ from the old config

- Format on save is on for every language with a formatter, including markdown (prettier). `<leader>uf` toggles it.
- The picker is snacks. Telescope is still installed, but only loads for the scripture picker, `<leader>jc` and obsidian.
- SQL uses vim-dadbod (`:DBUI`); per-project `.sqls/config.json` connections no longer apply.
- The markdown extra adds marksman and markdownlint-cli2 on top of harper-ls.
- The old keys: `<leader>f` (format) is now `<leader>cf`, `<leader>d` (diagnostic float) is `<leader>cd`, `<leader>q`
  (diagnostic list) is `<leader>xl`, `<leader>e` opens neo-tree instead of an oil float, `<leader>uv` is `<leader>rp`.
