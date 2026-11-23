-- Treesitter is LazyVim's; the language extras add their own parsers. These are the ones the extras do not cover.
return {
  {
    'nvim-treesitter/nvim-treesitter',
    opts = { ensure_installed = { 'c', 'css', 'hcl', 'make' } },
  },
}
