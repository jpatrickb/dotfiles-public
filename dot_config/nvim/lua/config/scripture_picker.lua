-- [custom] Scripture verse picker: search every verse of the standard works
-- by reference (`alma 32:21`) or by exact words (`faith hope things not
-- seen`), then insert it into the buffer. See parse_query for the rules.
--   <CR>   insert the verse as a linked blockquote below the cursor line
--   <C-l>  insert just the linked reference at the cursor
-- Also provides the `K` hover preview for a reference under the cursor.
-- Keymaps live in lua/config/keymaps.lua. Links come from
-- lua/config/scripture_links.lua.
--
-- Verse text is the public-domain bcbooks/scriptures-json "flat" edition
-- (https://github.com/bcbooks/scriptures-json), pinned to one commit and
-- downloaded on first use into stdpath('data')/scriptures (about 10 MB, not
-- tracked by chezmoi). Delete that directory to force a fresh download.
local M = {}

local links = require 'config.scripture_links'

local DATA_DIR = vim.fn.stdpath 'data' .. '/scriptures'
local SOURCE = 'https://raw.githubusercontent.com/bcbooks/scriptures-json/3bda76e40add4582165340ea6b1198dc6ad26ae1/flat/'
local FILES = {
  'old-testament-flat.json',
  'new-testament-flat.json',
  'book-of-mormon-flat.json',
  'doctrine-and-covenants-flat.json',
  'pearl-of-great-price-flat.json',
}

---@type { ref: string, text: string, lower: string, path: string?, chapter: string?, verse: integer? }[]?
local verses
-- Verse text keyed by '<volume/book>/<chapter>:<verse>' (the same
-- volume/book path scripture_links uses), for the hover preview.
---@type table<string, string>
local by_key = {}

--- Download any missing data file. Returns false (after notifying) on failure.
local function ensure_data()
  vim.fn.mkdir(DATA_DIR, 'p')
  for _, file in ipairs(FILES) do
    local path = DATA_DIR .. '/' .. file
    if not vim.uv.fs_stat(path) then
      vim.notify('Downloading ' .. file .. ' ...')
      vim.cmd.redraw()
      -- Download to a temp name so an interrupted download never leaves a
      -- truncated file that looks complete.
      local result = vim.system({ 'curl', '-fsSL', '-o', path .. '.part', SOURCE .. file }):wait()
      if result.code ~= 0 then
        vim.uv.fs_unlink(path .. '.part')
        vim.notify('Scripture download failed for ' .. file .. ': ' .. (result.stderr or ''), vim.log.levels.ERROR)
        return false
      end
      vim.uv.fs_rename(path .. '.part', path)
    end
  end
  return true
end

--- All verses in canonical order, loaded once per session.
local function load()
  if verses then return verses end
  if not ensure_data() then return nil end
  local list = {}
  local book_paths = {} -- data book name -> volume/book path, resolved once per book
  for _, file in ipairs(FILES) do
    local fd = assert(io.open(DATA_DIR .. '/' .. file, 'r'))
    local data = vim.json.decode(fd:read '*a')
    fd:close()
    for _, verse in ipairs(data.verses) do
      local entry = { ref = verse.reference, text = verse.text, lower = verse.text:lower() }
      table.insert(list, entry)
      local book, chapter, number = verse.reference:match '^(.-) (%d+):(%d+)$'
      if book then
        if book_paths[book] == nil then
          local found = links.find(verse.reference, false)[1]
          book_paths[book] = found and found.path or false
        end
        if book_paths[book] then
          entry.path, entry.chapter, entry.verse = book_paths[book], chapter, tonumber(number)
          by_key[('%s/%s:%s'):format(entry.path, chapter, number)] = verse.text
        end
      end
    end
  end
  verses = list
  return verses
end

--- Show the verse text for the scripture reference under the cursor in a
--- float. Works on plain and already-linked references; a chapter-only
--- reference shows the whole chapter. Returns false if the cursor is not on
--- a reference (so the caller can fall back to the normal `K`).
function M.hover()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local line = vim.api.nvim_get_current_line()
  local ref
  for _, found in ipairs(links.find(line, true, true)) do
    if col >= found.s and col <= found.e then ref = found end
  end
  if not ref or not load() then return false end

  local first, last = ref.verse or 1, ref.last or ref.verse or math.huge
  local lines = { '**' .. line:sub(ref.s, ref.e) .. '**' }
  for verse = first, last do
    local text = by_key[('%s/%d:%d'):format(ref.path, ref.chapter, verse)]
    if not text then break end
    vim.list_extend(lines, { '', ('**%d** %s'):format(verse, text) })
  end
  if #lines == 1 then
    vim.notify('No verse text found for ' .. line:sub(ref.s, ref.e), vim.log.levels.WARN)
    return true
  end
  local _, winid = vim.lsp.util.open_floating_preview(lines, 'markdown', { border = 'rounded', max_width = 90, wrap = true, focus_id = 'scripture-hover' })
  -- The float is a markdown buffer, so the markdown FileType autocmd turns
  -- spell on in it -- and scriptural English ("ye", "shalt") lights up.
  if winid then vim.wo[winid].spell = false end
  return true
end

--- `[Reference](url)` for a verse.
local function link(verse) return (links.linkify_line(verse.ref)) end

--- Insert the verse as a blockquote below the cursor line (or on it, if the
--- cursor line is blank), keeping a blank line before the quote.
local function insert_quote(verse)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  -- Reference on its own line, verse text below. The empty `>` line between
  -- them keeps them separate paragraphs, so the markdown formatter (prettier,
  -- proseWrap: always) doesn't flow the verse back up onto the reference line.
  local quote = { ('> **%s**'):format(link(verse)), '>', '> ' .. verse.text }
  local function blank(lnum)
    local text = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1]
    return text == nil or text:match '^%s*$' ~= nil
  end
  -- A blank cursor line is replaced; otherwise the quote goes below it.
  local first = blank(row) and row or row + 1
  local replaced = blank(row) and 1 or 0
  -- Pad with blank lines so the quote never runs into neighbouring text
  -- (a line directly after a blockquote is otherwise absorbed into it).
  local pad_before = not blank(first - 1)
  if pad_before then table.insert(quote, 1, '') end
  if not blank(first + replaced) then table.insert(quote, '') end
  vim.api.nvim_buf_set_lines(0, first - 1, first - 1 + replaced, false, quote)
  vim.api.nvim_win_set_cursor(0, { first + (pad_before and 1 or 0) + 2, 0 })
end

--- Where `term` starts a word in `text` (both lowercase), or nil. So `pray`
--- matches "pray", "prayer" and "prayeth" but not "spray".
local function find_word(text, term)
  local init = 1
  while true do
    local s, e = text:find(term, init, true)
    if not s then return nil end
    if s == 1 or not text:sub(s - 1, s - 1):match '%w' then return s, e end
    init = s + 1
  end
end

--- Turn the prompt into a query. Two kinds:
---   reference: a full book name plus a chapter, e.g. `alma 32`, `alma 32:2`,
---     `d&c 88:63-64`. The chapter (or, after a colon, the verse) is matched
---     as a prefix so results narrow as you type; `V-L` is a verse range.
---   words: anything else. Every word must start a word in the verse text.
local function parse_query(prompt)
  local q = vim.trim(prompt):lower():gsub('%s+', ' ')
  local book, chapter, rest = q:match '^(.-) (%d+)(.*)$'
  local path = book and links.book_path(book)
  if path then
    local verse, dash, last = rest:match '^:(%d*)(%-?)(%d*)$'
    if rest == '' then return { path = path, chapter_prefix = chapter } end
    if verse then
      return { path = path, chapter = chapter, verse_prefix = verse, range = dash ~= '', first = tonumber(verse), last = tonumber(last) }
    end
  end
  return { phrase = q, terms = vim.split(q, ' ', { plain = true, trimempty = true }) }
end

--- Telescope sorter for the two query kinds. Lower scores rank higher.
--- Reference queries and the empty prompt keep scripture order. Word queries
--- put verses containing the words as one phrase first, then shorter verses.
local function make_sorter()
  local sorters = require 'telescope.sorters'
  local last_prompt, query
  local function parsed(prompt)
    if prompt ~= last_prompt then
      last_prompt, query = prompt, parse_query(prompt)
    end
    return query
  end

  return sorters.Sorter:new {
    scoring_function = function(_, prompt, _, entry)
      local q, verse = parsed(prompt), entry.value
      if q.path then
        if verse.path ~= q.path then return -1 end
        if q.chapter_prefix then return vim.startswith(verse.chapter, q.chapter_prefix) and entry.index or -1 end
        if verse.chapter ~= q.chapter then return -1 end
        local ok
        if q.range then
          ok = verse.verse >= (q.first or 1) and verse.verse <= (q.last or math.huge)
        else
          ok = vim.startswith(tostring(verse.verse), q.verse_prefix)
        end
        return ok and entry.index or -1
      end
      if #q.terms == 0 then return entry.index end
      for _, term in ipairs(q.terms) do
        if not find_word(verse.lower, term) then return -1 end
      end
      local is_phrase = find_word(verse.lower, q.phrase) ~= nil
      return (is_phrase and 1 or 2) + #verse.text * 1e-4 + entry.index * 1e-10
    end,

    highlighter = function(_, prompt, display)
      local q = parsed(prompt)
      if q.path then return {} end
      local offset = (display:find('  ', 1, true) or 0) + 1 -- skip the reference
      local text = display:sub(offset + 1):lower()
      local highlights = {}
      for _, term in ipairs(q.terms) do
        local s, e = find_word(text, term)
        if s then table.insert(highlights, { start = s + offset, finish = e + offset }) end
      end
      return highlights
    end,
  }
end

--- Insert just the linked reference after the cursor.
local function insert_link(verse) vim.api.nvim_put({ link(verse) }, 'c', true, true) end

function M.pick()
  local all = load()
  if not all then return end

  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local previewers = require 'telescope.previewers'
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'

  local function on_select(insert)
    return function(prompt_bufnr)
      local entry = action_state.get_selected_entry()
      actions.close(prompt_bufnr)
      if entry then insert(entry.value) end
    end
  end

  pickers
    .new({}, {
      prompt_title = 'Scriptures (<CR> quote, <C-l> link only)',
      finder = finders.new_table {
        results = all,
        entry_maker = function(verse)
          local line = verse.ref .. '  ' .. verse.text
          return { value = verse, display = line, ordinal = line }
        end,
      },
      sorter = make_sorter(),
      previewer = previewers.new_buffer_previewer {
        title = 'Verse',
        define_preview = function(self, entry)
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { entry.value.ref, '', entry.value.text })
          vim.wo[self.state.winid].wrap = true
          vim.wo[self.state.winid].linebreak = true
        end,
      },
      attach_mappings = function(_, map)
        actions.select_default:replace(on_select(insert_quote))
        map({ 'i', 'n' }, '<C-l>', on_select(insert_link))
        return true
      end,
    })
    :find()
end

return M
