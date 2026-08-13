return {
  "stevearc/conform.nvim",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local conform = require("conform")

    conform.setup({
      formatters_by_ft = {
        javascript = { "prettier" },
        typescript = { "prettier" },
        javascriptreact = { "prettier" },
        typescriptreact = { "prettier" },
        css = { "prettier" },
        html = { "prettier" },
        json = { "prettier" },
        yaml = { "prettier" },
        markdown = { "prettier" },
        graphql = { "prettier" },
        liquid = { "prettier" },
        lua = { "stylua" },
        python = { "isort", "black" },
        c = { "clang_format" },
        cpp = { "clang_format" },
      },
      formatters = {
        clang_format = {
          -- Without a .clang-format in the tree, do nothing (no LLVM defaults).
          prepend_args = { "--fallback-style=none" },
        },
      },
      -- C/C++: don't format on save — Mason clang-format drifts from the
      -- repo pre-commit formatter. Use the hook (or <leader>cf) instead.
      format_on_save = function(bufnr)
        local ft = vim.bo[bufnr].filetype
        if ft == "c" or ft == "cpp" then
          return
        end
        return {
          async = false,
          timeout_ms = 1000,
        }
      end,
    })

    vim.keymap.set({ "n", "v" }, "<leader>cf", function()
      conform.format({
        async = false,
        timeout_ms = 1000,
      })
    end, { desc = "Format file or range (in visual mode)" })
  end,
}