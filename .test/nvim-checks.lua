-- Assertions run INSIDE a headless Neovim by .test/nvim.sh (never run this against your real config: the driver
-- gives Neovim a throwaway HOME). Output: one "PASS text" or "FAIL text [detail]" line per check.
-- Environment: CHK_MODE = native | journal | omarchy, CHK_TMP = a scratch directory, CHK_LOCK = the repo's lazy-lock.json.
local mode = vim.env.CHK_MODE or "native"
local tmp = vim.env.CHK_TMP

local function ok(cond, msg, detail)
  io.stdout:write((cond and "PASS " or "FAIL ") .. msg .. (cond and "" or ("  [" .. vim.inspect(detail):gsub("%s+", " ") .. "]")) .. "\n")
end

local lazy_config = require("lazy.core.config")
-- the fully merged `opts` table of a plugin (all specs that mention it, LazyVim's and ours)
local function opts_of(name)
  local plugin = lazy_config.plugins[name]
  if not plugin then return nil end
  return require("lazy.core.plugin").values(plugin, "opts", false)
end
local function has(list, value) return type(list) == "table" and vim.tbl_contains(list, value) end
local function mapped(mode_, lhs)
  local m = vim.fn.maparg(lhs, mode_, false, true)
  return type(m) == "table" and not vim.tbl_isempty(m), m
end

local wk_opts_before = vim.deepcopy(opts_of("which-key.nvim")) -- a COPY: which-key mutates its opts in place when it loads on VeryLazy

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.schedule(function()
      vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false }) -- headless never fires UIEnter
      vim.defer_fn(function()
        local good, err = xpcall(function()
          ---------------------------------------------------------------- startup
          ok(vim.v.errmsg == "", "startup: no error message was raised", vim.v.errmsg)
          ok(vim.tbl_isempty(lazy_config.spec.notifs), "lazy.nvim reports no spec problems (duplicate plugins, bad specs)", lazy_config.spec.notifs)
          ok(vim.g.colors_name == "aether", "the colour scheme from lua/plugins/theme.lua is applied (aether)", vim.g.colors_name)
          ok(vim.api.nvim_get_hl(0, { name = "Normal" }).bg == nil, "the editor background is transparent (plugin/after/transparency.lua ran after the theme)")

          ---------------------------------------------------------------- options
          ok(vim.o.relativenumber == true, "relativenumber is on", vim.o.relativenumber)
          ok(vim.o.wrap == false, "wrap is off", vim.o.wrap)
          ok(vim.o.scrolloff == 10, "scrolloff is 10", vim.o.scrolloff)
          ok(vim.o.exrc == true, "exrc is on (project-local .nvim.lua)", vim.o.exrc)
          ok(vim.o.concealcursor == "nc", "concealcursor is nc", vim.o.concealcursor)
          ok(vim.o.foldlevel == 99, "every file starts fully unfolded (foldlevel 99)", vim.o.foldlevel)
          ok(vim.g.autoformat == true, "format on save is ON (Omarchy's skeleton turns it off; here it is on)", vim.g.autoformat)

          ---------------------------------------------------------------- LazyVim pieces
          local want = {
            "ai.copilot-native", "coding.mini-surround", "editor.neo-tree", "formatting.prettier", "lang.go", "lang.markdown",
            "lang.python", "lang.rust", "lang.sql", "lang.terraform", "lang.typescript", "linting.eslint",
          }
          local missing = vim.tbl_filter(function(e) return not LazyVim.has_extra(e) end, want)
          ok(#missing == 0, "all 12 chosen LazyVim extras are enabled", missing)
          ok(LazyVim.pick.picker and LazyVim.pick.picker.name == "snacks", "the picker is snacks", LazyVim.pick.picker and LazyVim.pick.picker.name)
          ok(LazyVim.has("blink.cmp") and not LazyVim.has("nvim-cmp"), "completion is blink.cmp")
          ok(not LazyVim.has_extra("ai.copilot"), "the plugin-based copilot extra is NOT also enabled (they conflict)")

          ---------------------------------------------------------------- merged plugin options
          local blink = opts_of("blink.cmp") or {}
          ok(blink.keymap and blink.keymap.preset == "default", "blink: keymap preset is 'default' (Ctrl-y accepts)", blink.keymap)
          ok(blink.fuzzy and blink.fuzzy.implementation == "lua", "blink: pure-Lua fuzzy matcher", blink.fuzzy)
          local rm = opts_of("render-markdown.nvim") or {}
          ok(rm.callout and rm.callout.impression and rm.callout.act and rm.callout.ask, "render-markdown: the journal callouts (impression, act, ask) are configured", rm.callout)
          ok(rm.code ~= nil, "render-markdown: LazyVim's markdown-extra options are merged in with them", vim.tbl_keys(rm))
          local servers = (opts_of("nvim-lspconfig") or {}).servers or {}
          for _, s in ipairs({ "pyright", "ruff", "vtsls", "gopls", "terraformls", "marksman", "eslint", "harper_ls" }) do
            ok(servers[s] ~= nil, "language server configured: " .. s, vim.tbl_keys(servers))
          end
          ok(type(servers.pyright and servers.pyright.before_init) == "function", "pyright: venv detection hook is present")
          ok(servers.harper_ls and has(servers.harper_ls.filetypes, "markdown") and #servers.harper_ls.filetypes == 1, "harper-ls: markdown only", servers.harper_ls and servers.harper_ls.filetypes)
          ok(servers.harper_ls and servers.harper_ls.settings["harper-ls"].linters.SpellCheck == false, "harper-ls: its own spell checker is off")
          local mason = (opts_of("mason.nvim") or {}).ensure_installed
          for _, t in ipairs({ "checkmake", "golangci-lint", "stylua", "prettier", "tflint", "gofumpt", "goimports", "sqlfluff" }) do
            ok(has(mason, t), "Mason installs " .. t, mason)
          end
          local conform = (opts_of("conform.nvim") or {}).formatters_by_ft or {}
          ok(has(conform.lua, "stylua") and has(conform.markdown, "prettier") and has(conform.typescript, "prettier"), "conform: stylua for Lua, prettier for markdown and TypeScript", conform)
          local lint = (opts_of("nvim-lint") or {}).linters_by_ft or {}
          ok(has(lint.make, "checkmake") and has(lint.go, "golangcilint") and has(lint.markdown, "markdownlint-cli2"), "nvim-lint: makefile, go and markdown linters", lint)
          ok(has(lint.terraform, "tflint") and has(lint.terraform, "terraform_validate"), "nvim-lint: terraform runs tflint (ours) AND terraform validate (the extra's), the lists are merged", lint.terraform)
          local ts = (opts_of("nvim-treesitter") or {}).ensure_installed
          local ts_missing = vim.tbl_filter(function(p) return not has(ts, p) end, { "c", "css", "hcl", "make", "sql", "terraform", "go", "rust", "python", "markdown" })
          ok(#ts_missing == 0, "treesitter parsers requested: ours plus the extras'", ts_missing)
          ok((opts_of("oil.nvim") or {}).default_file_explorer == false, "oil does not hijack directories (neo-tree opens them)")
          local wk = (wk_opts_before or {}).spec or {}
          local groups = {}
          for _, s in ipairs(wk) do if type(s) == "table" and s.group then groups[s.group] = true end end
          ok(groups.journal and groups.make and groups.run, "which-key names the journal / make / run groups", vim.tbl_keys(groups))
          ok((opts_of("telescope.nvim") or {}).defaults.vimgrep_arguments[1] == "rg", "telescope keeps the ripgrep arguments that search hidden files")

          ---------------------------------------------------------------- laziness and removals
          ok(lazy_config.plugins["telescope.nvim"] and not lazy_config.plugins["telescope.nvim"]._.loaded, "telescope is installed but NOT loaded at startup (lazy)")
          ok(lazy_config.plugins["oil.nvim"] and not lazy_config.plugins["oil.nvim"]._.loaded, "oil is NOT loaded at startup (lazy)")
          ok(lazy_config.plugins["snacks.nvim"]._.loaded ~= nil, "snacks (the picker) is loaded")
          for _, gone in ipairs({ "LuaSnip", "toggleterm.nvim", "nvim-autopairs", "fidget.nvim", "copilot.vim", "sqls.nvim", "nvim-web-devicons" }) do
            ok(lazy_config.plugins[gone] == nil, "dropped plugin is not in the spec: " .. gone)
          end
          ok(lazy_config.plugins["neo-tree.nvim"] ~= nil and lazy_config.plugins["bufferline.nvim"] ~= nil and lazy_config.plugins["noice.nvim"] ~= nil, "neo-tree, bufferline and noice (LazyVim's) are present")
          ok(vim.fn.exists(":ToggleTerm") == 0, "the toggleterm command is gone")

          ---------------------------------------------------------------- keymaps
          local want_maps = {
            { "n", "<leader>sf" }, { "n", "<leader><leader>" }, { "n", "<leader>s." }, { "n", "<leader>e" }, { "n", "<leader>fe" },
            { "n", "<leader>E" }, { "n", "-" }, { "n", "<A-h>" }, { "n", "<A-l>" }, { "i", "<A-h>" }, { "i", "<A-l>" },
            { "t", "<A-h>" }, { "t", "<A-l>" }, { "n", "<leader>jl" }, { "n", "<leader>jL" }, { "n", "<leader>jv" },
            { "n", "<leader>mm" }, { "n", "<leader>rp" }, { "n", "<leader>sg" }, { "n", "<leader>cf" }, { "n", "<leader>uf" },
            { "n", "<leader>/" }, { "n", "<leader>ff" }, { "n", "<leader>," }, { "n", "<leader>cd" }, { "n", "<leader>xl" },
            { "n", "<A-j>" }, { "n", "<A-k>" }, { "n", "gsa" }, { "n", "gsd" }, { "n", "gsr" }, { "n", "s" },
          }
          local unmapped = {}
          for _, m in ipairs(want_maps) do
            if not mapped(m[1], m[2]) then unmapped[#unmapped + 1] = m[1] .. " " .. m[2] end
          end
          ok(#unmapped == 0, "all " .. #want_maps .. " expected keymaps exist", unmapped)
          -- every key docs/neovim.md tells you to press (the guide must not drift from the config); LSP keys (gd, gr, <leader>ca,
          -- <leader>cr, K) only exist once a language server attaches, so they are not checked here
          local documented = {
            "<leader>ge", "<leader>be", "<leader>bb", "<leader>bj", "<leader>bd", "<leader>bo", "<leader>bp", "<leader>bP",
            "<leader>br", "<leader>bl", "<S-h>", "<S-l>", "]b", "[b", "[B", "]B", "<leader>sw", "<leader>sk", "<leader>sc",
            "<leader>sr", "<leader>fr", "<leader>xx", "]d", "[d", "<leader><space>", "<leader>,", "<C-h>", "<C-l>",
          }
          local undoc = {}
          for _, lhs in ipairs(documented) do
            if not mapped("n", lhs) then undoc[#undoc + 1] = lhs end
          end
          ok(#undoc == 0, "all " .. #documented .. " extra keys that docs/neovim.md mentions exist", undoc)
          local e = select(2, mapped("n", "<leader>e"))
          ok((e.desc or ""):find("NeoTree") ~= nil, "<leader>e opens neo-tree", e.desc)
          ok(not mapped("n", "<leader>uv"), "the old toggleterm uv key (<leader>uv) is gone")
          local js, jc = mapped("n", "<leader>js"), mapped("n", "<leader>jc")
          if mode == "journal" then
            ok(js and jc, "journal keys <leader>js and <leader>jc exist where the journal does")
          else
            ok(not js and not jc, "journal keys <leader>js / <leader>jc do not exist where there is no journal")
          end

          ---------------------------------------------------------------- user commands, autocmds
          ok(vim.fn.exists(":GitBlameLine") == 2, ":GitBlameLine exists")
          ok(#vim.api.nvim_get_autocmds({ group = "custom-make-quickfix" }) == 1, "the :make -> quickfix autocmd exists")

          ---------------------------------------------------------------- a markdown buffer
          local md = (mode == "vault") and (vim.env.HOME .. "/Documents/personal/second-brain/note.md") or (tmp .. "/note.md")
          vim.fn.mkdir(vim.fn.fnamemodify(md, ":h"), "p")
          vim.fn.writefile({ "# One", "", "text", "", "## Two", "", "### Three", "deep line", "", "[[x]]" }, md)
          vim.cmd("edit " .. md)
          vim.wait(3000, function() return vim.bo.filetype == "markdown" end)
          ok(vim.bo.filetype == "markdown", "markdown filetype detected")
          ok(vim.wo.foldmethod == "expr", "markdown folds by expression (treesitter)", { vim.wo.foldmethod, vim.wo.foldexpr })
          ok(vim.fn.foldlevel(8) == 3 and vim.fn.foldlevel(5) == 2, "a line under ### is at fold level 3 and under ## at level 2", { vim.fn.foldlevel(8), vim.fn.foldlevel(5) })
          vim.cmd("setlocal foldlevel=2")
          ok(vim.fn.foldclosed(8) ~= -1 and vim.fn.foldclosed(5) == -1, "`:setl foldlevel=2` closes H3 and deeper but leaves H2 open", { vim.fn.foldclosed(8), vim.fn.foldclosed(5) })
          vim.cmd("setlocal foldlevel=99")
          ok(vim.wo.wrap and vim.wo.linebreak and vim.wo.spell, "markdown: wrap, linebreak and spell are on", { vim.wo.wrap, vim.wo.linebreak, vim.wo.spell })
          local bufmaps = {}
          for _, lhs in ipairs({ "]1", "]6", "[1", "[6", "K" }) do
            local m = vim.fn.maparg(lhs, "n", false, true)
            if type(m) == "table" and m.buffer == 1 then bufmaps[#bufmaps + 1] = lhs end
          end
          ok(#bufmaps == 5, "markdown: ]1..]6, [1..[6 heading jumps and the scripture K are buffer-local maps", bufmaps)
          vim.api.nvim_win_set_cursor(0, { 1, 0 })
          vim.cmd.normal("]3")
          ok(vim.api.nvim_win_get_cursor(0)[1] == 7, "]3 jumps to the next level-3 heading (line 7)", vim.api.nvim_win_get_cursor(0))
          vim.cmd.normal("[1")
          ok(vim.api.nvim_win_get_cursor(0)[1] == 1, "[1 jumps back to the level-1 heading", vim.api.nvim_win_get_cursor(0))
          vim.wait(1500, function() return lazy_config.plugins["render-markdown.nvim"]._.loaded ~= nil end)
          ok(lazy_config.plugins["render-markdown.nvim"]._.loaded ~= nil, "render-markdown loads for a markdown buffer")
          ok(vim.fn.exists(":RenderMarkdown") == 2, "the :RenderMarkdown command exists once loaded")
          if mode == "vault" then
            vim.wait(3000, function() return lazy_config.plugins["obsidian.nvim"] and lazy_config.plugins["obsidian.nvim"]._.loaded ~= nil end)
            ok(lazy_config.plugins["obsidian.nvim"] and lazy_config.plugins["obsidian.nvim"]._.loaded ~= nil, "a vault exists: obsidian.nvim loads for a markdown file in it")
            ok(vim.fn.exists(":Obsidian") == 2, "the :Obsidian command exists")
            ok(lazy_config.plugins["telescope.nvim"]._.loaded ~= nil, "obsidian pulled telescope in (its picker), and nothing broke")
            ok(((opts_of("obsidian.nvim") or {}).picker or {}).name == "telescope.nvim", "obsidian uses the telescope picker")
            -- (vim.v.errmsg is not usable here: which-key's own pcall'd trigger cleanup sets it whenever ANY buffer is switched, even in
            -- a plain markdown file without obsidian. So look for real Lua errors in :messages instead.)
            local msgs = vim.api.nvim_exec2("messages", { output = true }).output
            ok(not msgs:find("Error executing") and not msgs:find("E5108") and not msgs:find("E5113") and not msgs:find("stack traceback"), "no Lua error was reported while loading obsidian", msgs:sub(1, 300))
          else
            ok(lazy_config.plugins["obsidian.nvim"] == nil, "no vault on this machine: obsidian.nvim is not part of the setup at all")
          end

          ---------------------------------------------------------------- scripture tools (they call telescope directly)
          local scr = tmp .. "/scripture.md"
          vim.fn.writefile({ "Read John 3:16 today", "and Alma 32:21" }, scr)
          vim.cmd("edit " .. scr)
          vim.wait(2000, function() return vim.bo.filetype == "markdown" end)
          local linked1, e1 = pcall(function() require("config.scripture_links").linkify_current_line() end)
          ok(linked1 and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:find("[John 3:16](https://www.churchofjesuschrist.org/study/scriptures/nt/john/3", 1, true) ~= nil, "<leader>jl: a scripture reference on the line becomes a link", e1 or vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
          local linked2, e2 = pcall(function() require("config.scripture_links").linkify_buffer() end)
          ok(linked2 and vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]:find("[Alma 32:21](https://www.churchofjesuschrist.org/study/scriptures/bofm/alma/32", 1, true) ~= nil, "<leader>jL: references in the whole buffer become links", e2 or vim.api.nvim_buf_get_lines(0, 1, 2, false)[1])
          ok(select(1, pcall(require, "telescope.pickers")) and select(1, pcall(require, "telescope.actions.state")) and select(1, pcall(require, "telescope.previewers")), "the scripture picker's telescope modules load on demand (telescope is lazy)")

          ---------------------------------------------------------------- format on save (needs stylua installed by Mason)
          local lua_file = tmp .. "/ugly.lua"
          local stylua = vim.fn.stdpath("data") .. "/mason/bin/stylua"
          if vim.uv.fs_stat(stylua) then
            vim.fn.writefile({ "local   x=1", "return   { a=x }" }, lua_file)
            vim.cmd("edit " .. lua_file)
            vim.wait(2000, function() return vim.bo.filetype == "lua" end)
            vim.cmd("silent write")
            local after = table.concat(vim.fn.readfile(lua_file), "\n")
            ok(after:find("local x = 1", 1, true) ~= nil, "format on save: stylua reformatted an ugly Lua file when it was written", after)
            vim.g.autoformat = false
            vim.fn.writefile({ "local   y=2" }, lua_file)
            vim.cmd("edit! " .. lua_file)
            vim.cmd("silent write")
            ok(table.concat(vim.fn.readfile(lua_file), "\n") == "local   y=2", "with autoformat off (<leader>uf) the file is written as it is")
            vim.g.autoformat = true
          else
            io.stdout:write("PASS (skipped: stylua is not installed in this test's Mason; run the driver's setup)\n")
          end

          ---------------------------------------------------------------- machine-specific
          local clip_ok = pcall(require, "config.remote_clipboard")
          local hot = lazy_config.plugins["theme-hotreload"]
          local theme_path = vim.fn.stdpath("config") .. "/lua/plugins/theme.lua"
          local lst = vim.uv.fs_lstat(theme_path)
          if mode == "omarchy" then
            ok(clip_ok, "Omarchy: the remote-clipboard module is installed")
            ok(type(vim.g.clipboard) == "table", "Omarchy inside tmux: the clipboard provider is set up (copies reach the local clipboard)", vim.g.clipboard)
            ok(hot ~= nil, "Omarchy: the live theme-reload plugin is active")
            ok(lst and lst.type == "link", "Omarchy: lua/plugins/theme.lua is still Omarchy's symlink", lst and lst.type)
          else
            ok(not clip_ok, "not Omarchy: no remote-clipboard module")
            ok(vim.g.clipboard == nil, "not Omarchy, even inside tmux: Neovim's own clipboard handling is left alone (options.lua copes with the missing module)", vim.g.clipboard)
            ok(hot == nil, "not Omarchy: no live theme-reload plugin")
            ok(lst and lst.type == "file", "not Omarchy: lua/plugins/theme.lua is a regular file (the synced copy)", lst and lst.type)
          end

          ---------------------------------------------------------------- lockfile
          local f = io.open(vim.env.CHK_LOCK, "r")
          local lock = vim.json.decode(f:read("*a"))
          f:close()
          local drift = {}
          for name, entry in pairs(lock) do
            local dir = vim.fn.stdpath("data") .. "/lazy/" .. name
            local head = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "HEAD" })[1]
            if head ~= entry.commit then drift[#drift + 1] = name end
          end
          ok(#drift == 0, "every installed plugin is at the commit pinned in lazy-lock.json", drift)
        end, debug.traceback)
        if not good then io.stdout:write("FAIL the check script itself crashed  [" .. tostring(err):gsub("%s+", " ") .. "]\n") end
        vim.cmd("qa!")
      end, 1500)
    end)
  end,
})
