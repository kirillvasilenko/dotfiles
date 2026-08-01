return {
    "mason-org/mason.nvim",
    dependencies = {
      "mason-org/mason-lspconfig.nvim",
    },
    config = function()
      -- import mason
      local mason = require("mason")
  
      -- import mason-lspconfig
      local mason_lspconfig = require("mason-lspconfig")
  
      -- enable mason and configure icons
      mason.setup()
  
      mason_lspconfig.setup({
        -- list of servers for mason to install
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
        },
      })
    end,
  }