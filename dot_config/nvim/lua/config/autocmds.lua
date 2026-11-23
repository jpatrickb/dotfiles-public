-- Autocmds and user commands. Loaded by LazyVim on VeryLazy; LazyVim's defaults (yank highlight, wrap+spell for
-- markdown/text, auto-create dirs, ...) are in lua/lazyvim/config/autocmds.lua.
local function group(name) return vim.api.nvim_create_augroup('custom-' .. name, { clear = true }) end

-- Makefiles need real tabs.
vim.api.nvim_create_autocmd('FileType', {
  group = group 'make',
  pattern = 'make',
  callback = function()
    vim.bo.expandtab = false
    vim.bo.tabstop = 2
    vim.bo.shiftwidth = 2
    vim.bo.softtabstop = 0
  end,
})

-- Markdown: wrap at word boundaries (LazyVim already turns wrap and spell on), `K` on a scripture reference previews
-- the verse (anywhere else it is the usual LSP hover), and ]1..]6 / [1..[6 jump to the next/previous heading of
-- exactly that level (]] and [[ are the built-in "any heading" jumps).
vim.api.nvim_create_autocmd('FileType', {
  group = group 'markdown',
  pattern = 'markdown',
  callback = function(args)
    vim.opt_local.linebreak = true
    vim.keymap.set('n', 'K', function()
      if not require('config.scripture_picker').hover() then vim.lsp.buf.hover() end
    end, { buffer = args.buf, desc = 'Preview scripture reference, or LSP hover' })
    for level = 1, 6 do
      local pattern = '^' .. string.rep('#', level) .. '\\s'
      vim.keymap.set('n', ']' .. level, function() vim.fn.search(pattern, 'sW') end, { buffer = args.buf, desc = 'Next H' .. level })
      vim.keymap.set('n', '[' .. level, function() vim.fn.search(pattern, 'bsW') end, { buffer = args.buf, desc = 'Previous H' .. level })
    end
  end,
})

-- :make loads its results into the quickfix list; open the window when there are some. Vim's default 'errorformat'
-- already parses GNU Make's own errors and compiler errors, so no custom one is needed.
vim.api.nvim_create_autocmd('QuickFixCmdPost', {
  group = group 'make-quickfix',
  pattern = 'make',
  callback = function() vim.cmd 'cwindow' end,
})

-- :GitBlameLine prints the git blame for the current line.
vim.api.nvim_create_user_command('GitBlameLine', function()
  local line_number = vim.fn.line '.'
  local filename = vim.api.nvim_buf_get_name(0)
  print(vim.system({ 'git', 'blame', '-L', line_number .. ',+1', filename }):wait().stdout)
end, { desc = 'Print the git blame for the current line' })
