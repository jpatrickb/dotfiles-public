-- Language tooling. The LazyVim extras in lazyvim.json (python, typescript, go, rust, terraform, sql, markdown, prettier,
-- eslint) bring the language servers, formatters, linters and parsers; this file only holds what they do not cover or
-- what is configured differently here. `:Mason` shows what is installed, `:LazyExtras` the extras, `:ConformInfo` the
-- formatters (format on save is on; <leader>uf toggles it, <leader>cf formats now).

-- Which Python interpreter pyright should use for a project: an activated venv wins, else a venv directory in the
-- project root, else whatever is on $PATH. (root is nil for a .py file outside any project, hence the guards.)
local function python_path(root)
  if vim.env.VIRTUAL_ENV then return vim.env.VIRTUAL_ENV .. '/bin/python' end
  for _, d in ipairs { '.venv', 'venv', '.env' } do
    local p = root and (root .. '/' .. d .. '/bin/python')
    if p and vim.uv.fs_stat(p) then return p end
  end
  return vim.fn.exepath 'python3'
end

return {
  {
    'neovim/nvim-lspconfig',
    opts = {
      servers = {
        -- Point pyright at the project's venv. Must mutate config.settings in place: the client captured that table
        -- before before_init runs, so reassigning the field would be silently dropped.
        pyright = {
          before_init = function(_, config)
            config.settings.python = vim.tbl_deep_extend('force', config.settings.python or {}, {
              pythonPath = python_path(config.root_dir),
            })
          end,
        },

        -- harper-ls: offline grammar checker for prose, limited to markdown (its default filetypes also lint
        -- comments in most code languages). Its own spell checker is off so Neovim's built-in `spell` (on for
        -- markdown) is the only source of typo marks and `zg` the only dictionary. Rule names are the code shown on
        -- each diagnostic; set one to false to turn that whole rule off. Installed by Mason (package harper-ls).
        harper_ls = {
          filetypes = { 'markdown' },
          settings = {
            ['harper-ls'] = {
              linters = { SpellCheck = false, LongSentences = false, OxfordComma = false },
            },
          },
        },
      },
    },
  },

  -- Tools that are not language servers, installed by Mason.
  {
    'mason-org/mason.nvim',
    opts = { ensure_installed = { 'checkmake', 'golangci-lint', 'stylua' } },
  },

  -- Linters. Makefile diagnostics, and tflint for Terraform: the terraform extra installs tflint but only wires terraform
  -- validate, and a plain `opts = { linters_by_ft = { terraform = {...} } }` here would REPLACE the extra's list rather than
  -- add to it, so the lists are extended in a function. (The go and eslint linters come with their extras.)
  {
    'mfussenegger/nvim-lint',
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      for ft, linters in pairs { make = { 'checkmake' }, go = { 'golangcilint' }, terraform = { 'tflint' } } do
        local list = opts.linters_by_ft[ft] or {}
        for _, linter in ipairs(linters) do
          if not vim.tbl_contains(list, linter) then table.insert(list, linter) end
        end
        opts.linters_by_ft[ft] = list
      end
    end,
  },
}
