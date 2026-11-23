-- Small UI and editing pieces on top of LazyVim (which brings lualine, bufferline, noice, gitsigns, which-key,
-- todo-comments, mini.pairs, flash, ...).
return {
  -- guess-indent: detect and set the indentation of the file being edited.
  { 'NMAC427/guess-indent.nvim', lazy = false, opts = {} },

  -- quicker.nvim: a nicer quickfix / location list window.
  { 'stevearc/quicker.nvim', ft = 'qf', opts = {} },

  -- Names for the personal <leader> groups (lua/config/keymaps.lua) in the which-key popup.
  {
    'folke/which-key.nvim',
    opts = {
      spec = {
        { '<leader>j', group = 'journal' },
        { '<leader>m', group = 'make' },
        { '<leader>r', group = 'run' },
      },
    },
  },
}
