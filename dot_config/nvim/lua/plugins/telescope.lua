-- Telescope is no longer the picker (LazyVim uses snacks.picker: <leader>sf, <leader>sg, <leader>/ ...). It stays
-- installed, lazy (it loads the first time something uses it), for the three things that call it directly:
--   * the scripture verse picker and K preview (lua/config/scripture_picker.lua)
--   * the journal callouts search, <leader>jc (lua/config/keymaps.lua)
--   * obsidian.nvim's pickers (lua/plugins/notes.lua)
return {
  {
    'nvim-telescope/telescope.nvim',
    cmd = 'Telescope',
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = {
      defaults = {
        -- search hidden and ignored files too, but never .git
        vimgrep_arguments = {
          'rg',
          '--color=never',
          '--no-heading',
          '--with-filename',
          '--line-number',
          '--column',
          '--smart-case',
          '--hidden',
          '--no-ignore',
          '--glob',
          '!**/.git/*',
        },
      },
      pickers = {
        find_files = { find_command = { 'rg', '--files', '--hidden', '--no-ignore', '--glob', '!**/.git/*' } },
      },
    },
  },
}
