-- Completion: blink.cmp, which LazyVim configures. Snippets are Neovim's built-in snippet engine plus
-- friendly-snippets (LuaSnip is not used). Only the differences from LazyVim's setup are here.
return {
  {
    'saghen/blink.cmp',
    opts = {
      -- LazyVim's default is the "enter" preset (Enter accepts). "default": <C-y> accepts, <C-space> opens the menu
      -- or docs, <C-n>/<C-p> or the arrows select, <C-e> hides, <C-k> toggles signature help. `:help ins-completion`.
      keymap = { preset = 'default' },
      -- The pure-Lua fuzzy matcher: no prebuilt-binary download and nothing to build, so it behaves the same on every
      -- machine. (Set to "prefer_rust_with_warning" to use blink's faster Rust matcher where it is available.)
      fuzzy = { implementation = 'lua' },
    },
  },
}
