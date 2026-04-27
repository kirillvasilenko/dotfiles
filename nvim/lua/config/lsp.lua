
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspKeymaps", { clear = true }),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client then
      return
    end

    local bufnr = args.buf
    local builtin = require("telescope.builtin")

    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, {
        buffer = bufnr,
        desc = desc,
      })
    end

    local supports = function(method)
      return client:supports_method(method, bufnr)
    end

    if supports("textDocument/definition") then
      map("gd", builtin.lsp_definitions, "LSP definitions")
    end
    if supports("textDocument/references") then
      map("gr", builtin.lsp_references, "LSP references")
    end
    if supports("textDocument/implementation") then
      map("gi", builtin.lsp_implementations, "LSP implementations")
    end
    if supports("textDocument/typeDefinition") then
      map("gy", builtin.lsp_type_definitions, "LSP type definitions")
    end
    if supports("textDocument/hover") then
      map("K", vim.lsp.buf.hover, "LSP hover")
    end
    if supports("textDocument/rename") then
      map("<leader>rn", vim.lsp.buf.rename, "LSP rename")
    end
    if supports("textDocument/codeAction") then
      map("<leader>ca", vim.lsp.buf.code_action, "LSP code action")
    end

    if supports("textDocument/inlayHint") then
      vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
    end
  end,
})

