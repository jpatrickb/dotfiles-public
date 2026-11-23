-- Files. The explorer is neo-tree (the LazyVim extra): <leader>e toggles it, <leader>fe / <leader>fE for the root
-- dir / cwd. oil.nvim is kept for one thing only: editing the filesystem like a buffer.
--   -   open the parent directory of the current file in oil
-- Inside oil: <CR> opens, `-` goes up, edit lines then `:w` to apply (create/rename/move/delete); `g.` toggles hidden
-- files, `g?` shows help.
return {
  {
    'stevearc/oil.nvim',
    cmd = 'Oil',
    keys = { { '-', '<cmd>Oil<CR>', desc = 'Open parent directory (oil)' } },
    opts = {
      default_file_explorer = false, -- neo-tree opens `nvim <dir>`, not oil
      delete_to_trash = true, -- send deletions to the system trash (recoverable)
      skip_confirm_for_simple_edits = false, -- always confirm before writing changes
      view_options = { show_hidden = true }, -- show dotfiles (toggle with `g.`)
    },
  },
}
