vim.lsp.enable("clangd")

require("clangd_extensions").setup({})

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserClangdKeymaps", { clear = true }),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client or client.name ~= "clangd" then
      return
    end

    local bufnr = args.buf
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, {
        buffer = bufnr,
        desc = desc,
      })
    end

    if client:supports_method("textDocument/prepareTypeHierarchy", bufnr) then
      map("gh", "<cmd>ClangdTypeHierarchy<CR>", "Type hierarchy (parent/children classes)")
    end

    map("gs", require("clangd_extensions.switch_source_header").switch_source_header, "Switch source/header")
  end,
})
