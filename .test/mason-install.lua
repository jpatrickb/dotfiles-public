-- Run inside the container (and by hand) as: nvim --headless "+luafile .test/mason-install.lua" +qa
-- Installs every Mason package the config asks for: the `ensure_installed` list plus the package behind each enabled
-- language server, waits for all of them, and prints "MASON ok <name>" / "MASON FAILED <name>".
-- MASON_ONLY=a,b restricts it to those packages (used to try this script quickly outside the container).
local function say(s) io.stdout:write("MASON ", s, "\n") end
require("lazy").load({ plugins = { "mason.nvim", "mason-lspconfig.nvim" } })
local reg = require("mason-registry")
local refreshed = false
reg.refresh(function() refreshed = true end)
vim.wait(120000, function() return refreshed end)

local cfg = require("lazy.core.config")
local function opts_of(n) return require("lazy.core.plugin").values(cfg.plugins[n], "opts", false) end
local names, seen = {}, {}
local function add(n) if not seen[n] then seen[n] = true; names[#names + 1] = n end end
if vim.env.MASON_ONLY and vim.env.MASON_ONLY ~= "" then
  for n in vim.env.MASON_ONLY:gmatch("[^,]+") do add(n) end
else
  for _, n in ipairs(opts_of("mason.nvim").ensure_installed or {}) do add(n) end
  local map = require("mason-lspconfig").get_mappings().lspconfig_to_package
  for server, conf in pairs(opts_of("nvim-lspconfig").servers or {}) do
    if conf ~= false and (type(conf) ~= "table" or (conf.mason ~= false and conf.enabled ~= false)) and map[server] then add(map[server]) end
  end
end

local pending = 0
for _, n in ipairs(names) do
  local ok, pkg = pcall(reg.get_package, n)
  if not ok then say("FAILED " .. n .. " (not in the registry)")
  elseif not pkg:is_installable() then say("SKIP " .. n .. " (no build for this platform)")   -- e.g. checkmake has no linux arm64 binary
  elseif pkg:is_installed() then say("ok " .. n .. " (already installed)")
  elseif pkg:is_installing() then
    -- LazyVim's own startup install got there first: wait for it instead of starting a second one (that asserts)
    pending = pending + 1
    local function poll()
      if pkg:is_installing() then return vim.defer_fn(poll, 500) end
      pending = pending - 1
      say((pkg:is_installed() and "ok " or "FAILED ") .. n)
    end
    poll()
  else
    pending = pending + 1
    pkg:install():once("closed", function()
      pending = pending - 1
      say((pkg:is_installed() and "ok " or "FAILED ") .. n)
    end)
  end
end
vim.wait(1500000, function() return pending == 0 end, 500)
if pending > 0 then say("FAILED timeout, " .. pending .. " package(s) still installing") end
