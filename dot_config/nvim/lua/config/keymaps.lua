-- Keymaps. Loaded by LazyVim on VeryLazy; LazyVim's defaults are in lua/lazyvim/config/keymaps.lua and the plugin
-- specs. <leader> is <space>. Press <space> and wait to see everything (which-key).
local map = vim.keymap.set

-- Pickers (snacks.picker is LazyVim's picker). LazyVim already has <leader>ff / <leader><space> (files), <leader>sg
-- (grep), <leader>, (buffers), <leader>fr (recent); these are the old muscle-memory spellings, kept.
map('n', '<leader>sf', function() LazyVim.pick 'files'() end, { desc = 'Find Files (Root Dir)' })
map('n', '<leader><leader>', function() Snacks.picker.buffers { sort_lastused = true } end, { desc = 'Buffers' })
map('n', '<leader>s.', function() Snacks.picker.recent() end, { desc = 'Recent Files' })

-- Window navigation with Alt+h/l, also from insert and terminal mode (<C-h/j/k/l> work too, from LazyVim).
-- Alt+j/k are LazyVim's "move line down/up" (normal, insert and visual), so only h/l are used here.
map({ 't', 'i' }, '<A-h>', '<C-\\><C-n><C-w>h', { desc = 'Go to Left Window' })
map({ 't', 'i' }, '<A-l>', '<C-\\><C-n><C-w>l', { desc = 'Go to Right Window' })
map('n', '<A-h>', '<C-w>h', { desc = 'Go to Left Window' })
map('n', '<A-l>', '<C-w>l', { desc = 'Go to Right Window' })

-- Journal. The vault is local to the machine it lives on and never synced, so these keys only exist where it does.
local journal_sync = vim.fn.expand '~/Documents/personal/journal/scripts/git-sync.sh'
if vim.uv.fs_stat(journal_sync) then
  -- Save, commit + push via git-sync.sh, then quit. Stays open and shows the error if the sync fails, so a failed
  -- push never happens silently.
  map('n', '<leader>js', function()
    vim.cmd 'write'
    local result = vim.fn.system('bash ' .. journal_sync)
    if vim.v.shell_error == 0 then
      vim.cmd 'quitall'
    else
      vim.notify('git-sync failed: ' .. result, vim.log.levels.ERROR)
    end
  end, { desc = 'Journal Sync: save, commit, push, quit' })

  -- Every [!IMPRESSION] / [!ACT] / [!ASK] across all entries, newest first. Type e.g. "ACT" in the picker to narrow to
  -- one kind. Keep the list in sync with the render-markdown callouts in lua/plugins/notes.lua. Telescope is used here
  -- (lua/plugins/telescope.lua keeps it installed, lazy, for exactly this, the scripture picker and obsidian).
  map(
    'n',
    '<leader>jc',
    function()
      require('telescope.builtin').grep_string {
        prompt_title = 'Journal callouts',
        cwd = vim.fn.expand '~/Documents/personal/journal',
        search = '\\[!(IMPRESSION|ACT|ASK)\\]',
        use_regex = true,
        additional_args = { '--sortr', 'path', '--glob', '*.md' },
      }
    end,
    { desc = 'Journal Callouts: impressions, actions, questions' }
  )
end

-- Scripture tools (lua/config/scripture_links.lua, lua/config/scripture_picker.lua). Not tied to the journal directory.
map('n', '<leader>jl', function() require('config.scripture_links').linkify_current_line() end, { desc = 'Link scripture references on this line' })
map('n', '<leader>jL', function() require('config.scripture_links').linkify_buffer() end, { desc = 'Link scripture references in whole buffer' })
map('n', '<leader>jv', function() require('config.scripture_picker').pick() end, { desc = 'Verse search: find a verse and insert it' })

-- :make runs 'makeprg' and fills the quickfix list (autocmds.lua opens the window).
map('n', '<leader>mm', '<cmd>make<CR>', { desc = 'Make: run makeprg, fill quickfix' })

-- Run the current Python file with uv in a floating terminal that stays open so the output can be read.
map('n', '<leader>rp', function()
  if vim.bo.filetype ~= 'python' then
    vim.notify('Not a python file', vim.log.levels.WARN)
    return
  end
  if vim.bo.modified then vim.cmd 'write' end
  Snacks.terminal({ 'uv', 'run', vim.fn.expand '%:p' }, {
    win = { position = 'float' },
    auto_close = false, -- keep the output on screen after the program exits
  })
end, { desc = 'Run Python file with uv (float)' })
