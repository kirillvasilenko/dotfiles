return {
  "mason-org/mason.nvim",
  dependencies = {
    "neovim/nvim-lspconfig",
    "mason-org/mason-lspconfig.nvim",
    "hrsh7th/cmp-nvim-lsp",
    "WhoIsSethDaniel/mason-tool-installer.nvim",
  },
  config = function()
    local capabilities = require("cmp_nvim_lsp").default_capabilities()

    -- Must run before mason-lspconfig enables servers.
    vim.lsp.config("*", {
      capabilities = capabilities,
    })

    -- Must be registered before clangd starts, or we miss fileStatus / index progress.
    require("kir.lsp.clangd_ready")

    vim.lsp.config("clangd", {
      init_options = {
        clangdFileStatus = true,
      },
    })

    vim.lsp.config("lua_ls", {
      settings = {
        Lua = {
          diagnostics = {
            globals = { "vim" },
          },
          completion = {
            callSnippet = "Replace",
          },
        },
      },
    })

    -- Light grammar/spell on code comments. Markdown is handled by ltex_plus only.
    local harper_filetypes = vim.tbl_filter(function(ft)
      return ft ~= "markdown"
    end, vim.deepcopy(vim.lsp.config.harper_ls.filetypes or {}))

    vim.lsp.config("harper_ls", {
      filetypes = harper_filetypes,
      settings = {
        ["harper-ls"] = {
          linters = {
            SpellCheck = true,
            SpelledNumbers = false,
            AnA = true,
            SentenceCapitalization = true,
            UnclosedQuotes = true,
            WrongApostrophe = false,
            LongSentences = true,
            RepeatedWords = true,
            Spaces = true,
            CorrectNumberSuffix = true,
          },
          diagnosticSeverity = "hint",
          dialect = "American",
        },
      },
    })

    -- Strong LanguageTool grammar/spell for Markdown (Obsidian notes, etc.).
    vim.lsp.config("ltex_plus", {
      filetypes = { "markdown" },
      settings = {
        ltex = {
          enabled = { "markdown" },
          language = "en-US",
          checkFrequency = "edit",
          diagnosticSeverity = "information",
          additionalRules = {
            enablePickyRules = true,
          },
        },
      },
    })

    require("mason").setup()

    -- nvim-lspconfig must be on runtimepath before this runs.
    -- automatic_enable (default true) calls vim.lsp.enable() for installed servers.
    require("mason-lspconfig").setup({
      ensure_installed = {
        "ts_ls",
        "html",
        "cssls",
        "tailwindcss",
        "svelte",
        "lua_ls",
        "graphql",
        "emmet_ls",
        "prismals",
        "pyright",
        "clangd",
        "sqls",
        "harper_ls",
        "ltex_plus",
      },
    })

    require("mason-tool-installer").setup({
      ensure_installed = {
        "prettier", -- prettier formatter
        "stylua", -- lua formatter
        "isort", -- python formatter
        "black", -- python formatter
        "pylint", -- python linter
        "clang-format", -- c/c++ formatter
        -- "cpplint", -- c/c++ linter (Google style)
      },
    })
  end,
}
