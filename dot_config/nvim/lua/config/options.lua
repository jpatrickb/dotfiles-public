-- Options. Loaded by LazyVim before lazy.nvim starts; LazyVim's own defaults are in
-- lua/lazyvim/config/options.lua inside the LazyVim plugin (:LazyVim shows where).

-- Omarchy only: this module ships to Omarchy machines alone (see .chezmoiignore). It makes yanks made inside
-- tmux, ssh or herdr reach the local clipboard. Anywhere else the module does not exist, which is fine.
local ok, remote_clipboard = pcall(require, 'config.remote_clipboard')
if ok then
  remote_clipboard.setup()
elseif not tostring(remote_clipboard):find("module 'config.remote_clipboard' not found", 1, true) then
  error(remote_clipboard) -- the module exists but is broken: do not hide that
end

vim.g.have_nerd_font = true

-- Personal choices that differ from LazyVim's defaults.
vim.o.wrap = false -- no soft wrap (markdown buffers turn it on in lua/config/autocmds.lua)
vim.o.scrolloff = 10 -- LazyVim: 4
vim.o.exrc = true -- source a project's own .nvim.lua / .exrc (Neovim asks once whether to trust it, see :help trust)
vim.o.concealcursor = 'nc' -- keep concealed text (LaTeX, markdown links) concealed on the cursor line in n and c modes

-- Folding: LazyVim folds with treesitter (every file starts fully open). In markdown that gives one fold per heading
-- section, nested by heading level, so `:setl foldlevel=2` closes H3 and deeper, as the old MarkdownFold() setup did.

-- Omarchy's skeleton turns relativenumber off and autoformat off; here relative numbers stay on (LazyVim's default)
-- and format-on-save stays on (toggle with <leader>uf).
