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
        markdown = { "prettier_markdown" },
        graphql = { "prettier" },
        liquid = { "prettier" },
        lua = { "stylua" },
        python = { "isort", "black" },
        c = { "clang_format" },
        cpp = { "clang_format" },
      },
      formatters = {
        black = {
          prepend_args = { "--line-length", "120" },
        },
        clang_format = {
          -- Without a .clang-format in the tree, do nothing (no LLVM defaults).
          prepend_args = { "--fallback-style=none" },
        },
        -- Separate from JS prettier: wrap prose, leave other prettier defaults alone.
        prettier_markdown = {
          command = "prettier",
          args = {
            "--stdin-filepath",
            "$FILENAME",
            "--parser",
            "markdown",
            "--prose-wrap",
            "always",
            "--print-width",
            "120",
          },
        },
      },
      -- C/C++/Python: don't format on save — Mason tools drift from repo
      -- style (ya style / flake8). Use the hook (or <leader>cf) instead.
      format_on_save = function(bufnr)
        local ft = vim.bo[bufnr].filetype
        if ft == "c" or ft == "cpp" or ft == "python" then
          return
        end
        return {
          async = false,
          timeout_ms = 5000,
        }
      end,
    })

    vim.keymap.set({ "n", "v" }, "<leader>cf", function()
      conform.format({
        async = false,
        timeout_ms = 5000,
      })
    end, { desc = "Format file or range (in visual mode)" })
  end,
}