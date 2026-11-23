-- [custom] Notes & writing: render-markdown.nvim (markdown rendering),
-- render-latex.nvim (inline LaTeX), obsidian.nvim (vault notes), baleia.nvim
-- (ANSI color rendering, used by the coding-projects exrc -- see its
-- lua-line comment below).

-- [custom] The personal vault is local to THIS machine only, never
-- synced -- guarded by existence so they're inert everywhere else. Other
-- machines define their own vault(s) in an untracked
-- lua/obsidian_workspaces_local.lua (same shape, see that file) instead of
-- editing this shared config.
local function existing_workspaces(candidates)
  local ws = {}
  for _, w in ipairs(candidates) do
    if vim.uv.fs_stat(vim.fn.expand(w.path)) then table.insert(ws, w) end
  end
  return ws
end

local obsidian_workspaces = existing_workspaces {
  { name = 'personal', path = '~/Documents/personal/second-brain' },
}

local ok, local_workspaces = pcall(require, 'obsidian_workspaces_local')
if ok and type(local_workspaces) == 'table' then vim.list_extend(obsidian_workspaces, local_workspaces) end

-- [custom] Journal callouts, on top of render-markdown's built-in
-- GitHub/Obsidian set. Keep the list in sync with the <leader>jc picker in
-- lua/config/keymaps.lua.
local journal_callouts = {
  impression = { raw = '[!IMPRESSION]', rendered = '󰌶 Impression', highlight = 'RenderMarkdownHint', category = 'journal' },
  act = { raw = '[!ACT]', rendered = '󰄬 Act', highlight = 'RenderMarkdownSuccess', category = 'journal' },
  ask = { raw = '[!ASK]', rendered = '󰘥 Ask', highlight = 'RenderMarkdownWarn', category = 'journal' },
}

-- [custom] render-markdown only colours a callout's first line, and does it
-- with overlay virtual text, which stops at the window edge instead of
-- soft-wrapping. Paint every line of a journal callout's blockquote with the
-- callout's highlight so the colour covers the whole block, wrapped or not.
local callout_body_ns = vim.api.nvim_create_namespace 'custom-callout-body'
local function highlight_callout_bodies(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, callout_body_ns, 0, -1)
  local hl
  for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if not line:match '^%s*>' then
      hl = nil
    else
      local kind = line:match '^%s*>%s*%[!(%a+)%]'
      if kind then
        local callout = journal_callouts[kind:lower()]
        hl = callout and callout.highlight
      end
      if hl then vim.api.nvim_buf_set_extmark(bufnr, callout_body_ns, i - 1, 0, { end_col = #line, hl_group = hl }) end
    end
  end
end

return {
  -- render-markdown.nvim - render markdown inline. LazyVim's markdown extra already installs and configures it
  -- (treesitter and the icons come from LazyVim); this adds the journal callouts. lazy.nvim merges `opts` from both.
  {
    'MeanderingProgrammer/render-markdown.nvim',
    -- The marker must be the first line of its own blockquote (blank line before it) for render-markdown to swap
    -- in the icon.
    opts = { callout = journal_callouts },
    config = function(_, opts)
      require('render-markdown').setup(opts)

      local function refresh(bufnr)
        if vim.bo[bufnr].filetype == 'markdown' then highlight_callout_bodies(bufnr) end
      end
      vim.api.nvim_create_autocmd({ 'FileType', 'BufEnter', 'TextChanged', 'TextChangedI' }, {
        desc = 'Colour the full body of journal callouts',
        group = vim.api.nvim_create_augroup('custom-callout-body', { clear = true }),
        callback = function(args) refresh(args.buf) end,
      })
      -- This plugin loads on the first markdown buffer's FileType event, so
      -- that buffer has already missed the autocmd above.
      refresh(vim.api.nvim_get_current_buf())
    end,
  },

  -- render-latex.nvim - render LaTeX math inline in markdown.
  --  Auto-downloads a prebuilt Rust worker on first load (`:RenderLatex install`
  --  to retry if that fails). Needs a terminal that speaks the Kitty graphics
  --  protocol (or Neovim's image API). Not every terminal does: foot, Omarchy's
  --  terminal, very likely does not (untested), so math may stay as plain text there.
  {
    'techwizrd/render-latex.nvim',
    ft = 'markdown',
    -- [custom] explicit `config` rather than bare `opts`: lazy.nvim's default opts
    -- handler derives the module to require from the plugin name ("render-latex"),
    -- but the actual module is `render_latex` (underscore) -- avoid relying on the
    -- guess resolving correctly.
    opts = {
      render = {
        preset = 'match_text', -- size math to surrounding text ('compact' / 'presentation')
        inline = 'conceal', -- replace inline math with its render
        inline_symbols = true,
        live_preview = true,
        hide_on_cmdline = false,
      },
    },
    config = function(_, opts) require('render_latex').setup(opts) end,
  },

  -- obsidian.nvim - work with Obsidian vaults from Neovim.
  --  ripgrep must be on $PATH (it is) for search/completion.
  --  NOTE: macOS image-paste needs `pngpaste` (brew install pngpaste) - optional.
  --
  -- [custom] Using the obsidian-nvim/obsidian.nvim community fork, not the
  -- original epwalsh/obsidian.nvim: the original's last release was v3.9.0
  -- in July 2024 and it's seen no commits since April 2026, while the fork
  -- ships commits daily and continues the same v3.x version scheme (so the
  -- `version = 'v3.*'` pin below still applies). This also fixes completion:
  -- the original never had blink.cmp support at all (only nvim-cmp), so the
  -- `completion.blink = true` setting below used to be silently ignored.
  -- The fork replaced per-engine completion sources with an in-process LSP,
  -- which just works through blink's default 'lsp' source (lua/plugins/completion.lua
  -- already includes 'lsp' with no per_filetype override) -- no extra wiring needed.
  {
    'obsidian-nvim/obsidian.nvim',
    version = 'v3.*',
    ft = 'markdown',
    enabled = #obsidian_workspaces > 0,
    dependencies = {
      'nvim-lua/plenary.nvim',
      -- Loaded eagerly alongside obsidian (rather than left to its own `cmd`
      -- trigger) since obsidian's picker integration calls into telescope
      -- directly rather than through the `:Telescope` command.
      'nvim-telescope/telescope.nvim',
    },
    opts = {
      -- [custom] The fork nags with a deprecation notice on every markdown buffer
      -- otherwise ("legacy_commands is deprecated... will be removed in 4.0").
      -- Nothing in this config binds a keymap to an old :ObsidianX command name,
      -- so there's nothing to break by switching to the new `:Obsidian <subcommand>`
      -- style now instead of later.
      legacy_commands = false,

      workspaces = obsidian_workspaces,

      -- Disable obsidian's own markdown UI so it doesn't fight render-markdown.nvim,
      -- which already handles concealment/rendering for this config.
      ui = { enable = false },

      -- Use telescope (kept installed, lazy, by lua/plugins/telescope.lua) for the quick-switch / search pickers.
      picker = { name = 'telescope.nvim' },

      -- [custom] `nvim_cmp`/`blink` completion-engine keys don't exist in this fork's
      -- config schema anymore (completion is the in-process LSP mentioned above) --
      -- min_chars is still a real option, so that's all that's left here.
      completion = {
        min_chars = 2,
      },
    },
  },

  -- baleia.nvim - renders real ANSI color codes as highlights.
  --  Only used by ~/Documents/personal/coding-projects/.nvim.lua (a project-local
  --  exrc, see `:help exrc`), which does `pcall(require, 'baleia')` and falls back
  --  to plain-text output if it isn't loaded. Declared here (lazy, no trigger) so
  --  it installs/updates via :Lazy like every other plugin, instead of being cloned
  --  ad hoc by that exrc file the way `vim.pack.add` used to.
  {
    'm00qek/baleia.nvim',
    lazy = true,
  },
}
