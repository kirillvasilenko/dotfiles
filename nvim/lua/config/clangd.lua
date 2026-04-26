vim.lsp.enable("clangd")

require("clangd_extensions").setup({})

vim.keymap.set("n", "gh", "<cmd>ClangdTypeHierarchy<CR>", {
  desc = "Type hierarchy (parent/children classes)"
})

vim.keymap.set("n", "gs", require("clangd_extensions.switch_source_header").switch_source_header, { 
  desc = "Switch source/header"
})
