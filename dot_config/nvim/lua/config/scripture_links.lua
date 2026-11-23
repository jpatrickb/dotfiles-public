-- [custom] Scripture linkify: turn plain references like `2 Nephi 32:9`,
-- `D&C 88:63-64` or `Matthew 16:24–25` into markdown links to
-- churchofjesuschrist.org. No scripture data needed -- the URLs are built
-- from the reference alone. Keymaps live in lua/config/keymaps.lua.
--
-- Rules:
--   * Book names are matched case-insensitively and must be written in full
--     (plus the few short forms listed below, e.g. `D&C`).
--   * `Book C:V` and `Book C:V-V` (hyphen or en dash) are always linked.
--   * Chapter-only references (`Isaiah 58`) are linked only by the
--     current-line command, since `Mark 5` etc. is too ambiguous to do
--     buffer-wide.
--   * Text already inside a markdown link is left alone, so both commands
--     are safe to run repeatedly.
local M = {}

local BASE = 'https://www.churchofjesuschrist.org/study/scriptures/'

-- { volume, book slug, name, aliases... } -- slugs are the site's URL segments.
local BOOKS = {
  { 'ot', 'gen', 'Genesis' },
  { 'ot', 'ex', 'Exodus' },
  { 'ot', 'lev', 'Leviticus' },
  { 'ot', 'num', 'Numbers' },
  { 'ot', 'deut', 'Deuteronomy' },
  { 'ot', 'josh', 'Joshua' },
  { 'ot', 'judg', 'Judges' },
  { 'ot', 'ruth', 'Ruth' },
  { 'ot', '1-sam', '1 Samuel' },
  { 'ot', '2-sam', '2 Samuel' },
  { 'ot', '1-kgs', '1 Kings' },
  { 'ot', '2-kgs', '2 Kings' },
  { 'ot', '1-chr', '1 Chronicles' },
  { 'ot', '2-chr', '2 Chronicles' },
  { 'ot', 'ezra', 'Ezra' },
  { 'ot', 'neh', 'Nehemiah' },
  { 'ot', 'esth', 'Esther' },
  { 'ot', 'job', 'Job' },
  { 'ot', 'ps', 'Psalms', 'Psalm' },
  { 'ot', 'prov', 'Proverbs' },
  { 'ot', 'eccl', 'Ecclesiastes' },
  { 'ot', 'song', 'Song of Solomon', "Solomon's Song" },
  { 'ot', 'isa', 'Isaiah' },
  { 'ot', 'jer', 'Jeremiah' },
  { 'ot', 'lam', 'Lamentations' },
  { 'ot', 'ezek', 'Ezekiel' },
  { 'ot', 'dan', 'Daniel' },
  { 'ot', 'hosea', 'Hosea' },
  { 'ot', 'joel', 'Joel' },
  { 'ot', 'amos', 'Amos' },
  { 'ot', 'obad', 'Obadiah' },
  { 'ot', 'jonah', 'Jonah' },
  { 'ot', 'micah', 'Micah' },
  { 'ot', 'nahum', 'Nahum' },
  { 'ot', 'hab', 'Habakkuk' },
  { 'ot', 'zeph', 'Zephaniah' },
  { 'ot', 'hag', 'Haggai' },
  { 'ot', 'zech', 'Zechariah' },
  { 'ot', 'mal', 'Malachi' },

  { 'nt', 'matt', 'Matthew' },
  { 'nt', 'mark', 'Mark' },
  { 'nt', 'luke', 'Luke' },
  { 'nt', 'john', 'John' },
  { 'nt', 'acts', 'Acts' },
  { 'nt', 'rom', 'Romans' },
  { 'nt', '1-cor', '1 Corinthians' },
  { 'nt', '2-cor', '2 Corinthians' },
  { 'nt', 'gal', 'Galatians' },
  { 'nt', 'eph', 'Ephesians' },
  { 'nt', 'philip', 'Philippians' },
  { 'nt', 'col', 'Colossians' },
  { 'nt', '1-thes', '1 Thessalonians' },
  { 'nt', '2-thes', '2 Thessalonians' },
  { 'nt', '1-tim', '1 Timothy' },
  { 'nt', '2-tim', '2 Timothy' },
  { 'nt', 'titus', 'Titus' },
  { 'nt', 'philem', 'Philemon' },
  { 'nt', 'heb', 'Hebrews' },
  { 'nt', 'james', 'James' },
  { 'nt', '1-pet', '1 Peter' },
  { 'nt', '2-pet', '2 Peter' },
  { 'nt', '1-jn', '1 John' },
  { 'nt', '2-jn', '2 John' },
  { 'nt', '3-jn', '3 John' },
  { 'nt', 'jude', 'Jude' },
  { 'nt', 'rev', 'Revelation' },

  { 'bofm', '1-ne', '1 Nephi' },
  { 'bofm', '2-ne', '2 Nephi' },
  { 'bofm', 'jacob', 'Jacob' },
  { 'bofm', 'enos', 'Enos' },
  { 'bofm', 'jarom', 'Jarom' },
  { 'bofm', 'omni', 'Omni' },
  { 'bofm', 'w-of-m', 'Words of Mormon' },
  { 'bofm', 'mosiah', 'Mosiah' },
  { 'bofm', 'alma', 'Alma' },
  { 'bofm', 'hel', 'Helaman' },
  { 'bofm', '3-ne', '3 Nephi' },
  { 'bofm', '4-ne', '4 Nephi' },
  { 'bofm', 'morm', 'Mormon' },
  { 'bofm', 'ether', 'Ether' },
  { 'bofm', 'moro', 'Moroni' },

  { 'dc-testament', 'dc', 'Doctrine and Covenants', 'D&C' },

  { 'pgp', 'moses', 'Moses' },
  { 'pgp', 'abr', 'Abraham' },
  { 'pgp', 'js-m', 'Joseph Smith—Matthew', 'Joseph Smith-Matthew', 'JS—M', 'JS-M' },
  { 'pgp', 'js-h', 'Joseph Smith—History', 'Joseph Smith-History', 'JS—H', 'JS-H' },
  { 'pgp', 'a-of-f', 'Articles of Faith' },
}

-- Flat alias list, longest first, so `1 John` claims its text before `John`
-- and `Words of Mormon` before `Mormon`.
local ALIASES = {}
for _, book in ipairs(BOOKS) do
  for i = 3, #book do
    table.insert(ALIASES, { name = book[i]:lower(), path = book[1] .. '/' .. book[2] })
  end
end
table.sort(ALIASES, function(a, b) return #a.name > #b.name end)

--- The `volume/book` URL path for a full book name or alias (any case), or nil.
function M.book_path(name)
  name = vim.trim(name):lower()
  for _, alias in ipairs(ALIASES) do
    if alias.name == name then return alias.path end
  end
end

local EN_DASH = '\226\128\147'

local function overlaps(spans, s, e)
  for _, span in ipairs(spans) do
    if s <= span[2] and e >= span[1] then return true end
  end
  return false
end

--- Spans (1-based, inclusive) of existing `[text](url)` links in `line`.
local function link_spans(line)
  local spans, init = {}, 1
  while true do
    local s, e = line:find('%b[]%b()', init)
    if not s then break end
    table.insert(spans, { s, e })
    init = e + 1
  end
  return spans
end

--- Find the references in `line` that are not already linked.
---@param line string
---@param chapter_only boolean also match `Book C` with no verse
---@param include_linked? boolean also match references inside existing links
---@return { s: integer, e: integer, url: string, path: string, chapter: integer, verse: integer?, last: integer? }[] sorted by position
function M.find(line, chapter_only, include_linked)
  local lower = line:lower()
  local taken = include_linked and {} or link_spans(line)
  local found = {}
  for _, alias in ipairs(ALIASES) do
    local init = 1
    while true do
      local s, e = lower:find(alias.name, init, true)
      if not s then break end
      init = e + 1
      local boundary = s == 1 or not lower:sub(s - 1, s - 1):match '[%w]'
      local rest = line:sub(e + 1)
      local chapter, verse = rest:match '^ (%d+):(%d+)'
      local ref_end, url, last
      if boundary and chapter then
        ref_end = e + #chapter + #verse + 2
        local tail = line:sub(ref_end + 1)
        last = tail:match '^%-(%d+)'
        local dash_len = 1
        if not last then
          last = tail:match('^' .. EN_DASH .. '(%d+)')
          dash_len = #EN_DASH
        end
        local id = 'p' .. verse
        if last then
          ref_end = ref_end + dash_len + #last
          id = id .. '-p' .. last
        end
        url = ('%s%s/%s?lang=eng&id=%s#p%s'):format(BASE, alias.path, chapter, id, verse)
      elseif boundary and chapter_only then
        chapter = rest:match '^ (%d+)'
        local after = chapter and line:sub(e + #chapter + 2, e + #chapter + 2) or ''
        if chapter and not after:match '[%w]' then
          ref_end = e + #chapter + 1
          url = ('%s%s/%s?lang=eng'):format(BASE, alias.path, chapter)
        end
      end
      if url and not overlaps(taken, s, ref_end) then
        table.insert(taken, { s, ref_end })
        table.insert(found, {
          s = s,
          e = ref_end,
          url = url,
          path = alias.path,
          chapter = tonumber(chapter),
          verse = tonumber(verse),
          last = tonumber(last),
        })
      end
    end
  end
  table.sort(found, function(a, b) return a.s < b.s end)
  return found
end

--- Return `line` with its references turned into markdown links, and how many.
function M.linkify_line(line, chapter_only)
  local refs = M.find(line, chapter_only)
  for i = #refs, 1, -1 do
    local ref = refs[i]
    line = ('%s[%s](%s)%s'):format(line:sub(1, ref.s - 1), line:sub(ref.s, ref.e), ref.url, line:sub(ref.e + 1))
  end
  return line, #refs
end

--- Linkify the cursor line, including chapter-only references.
function M.linkify_current_line()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line, count = M.linkify_line(vim.api.nvim_get_current_line(), true)
  if count > 0 then vim.api.nvim_buf_set_lines(0, row - 1, row, false, { line }) end
  vim.notify(('Linked %d scripture reference%s'):format(count, count == 1 and '' or 's'))
end

--- Linkify every `Book C:V` reference in the buffer, skipping YAML
--- frontmatter and fenced code blocks.
function M.linkify_buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local total, in_fence = 0, false
  local in_frontmatter = lines[1] == '---'
  for i, line in ipairs(lines) do
    if in_frontmatter then
      if i > 1 and line == '---' then in_frontmatter = false end
    elseif line:match '^%s*```' then
      in_fence = not in_fence
    elseif not in_fence then
      local new, count = M.linkify_line(line, false)
      if count > 0 then
        vim.api.nvim_buf_set_lines(0, i - 1, i, false, { new })
        total = total + count
      end
    end
  end
  vim.notify(('Linked %d scripture reference%s'):format(total, total == 1 and '' or 's'))
end

return M
