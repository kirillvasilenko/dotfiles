--vim.lsp.config["clangd"] = {
--  cmd = {
--    "clangd",
--    "--log=verbose",
--    "--pretty",
--  }
--}
local capabilities = require("cmp_nvim_lsp").default_capabilities()

vim.lsp.config("clangd", {
  capabilities = capabilities,
})

vim.lsp.enable("clangd")

-- we have them in the telescope integration
--vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Go to definition" })
--vim.keymap.set("n", "gi", vim.lsp.buf.implementation, { desc = "Go to implementations" })
--vim.keymap.set("n", "gr", vim.lsp.buf.references, { desc = "Find references" })

vim.lsp.inlay_hint.enable(true)
vim.keymap.set("n", "K", vim.lsp.buf.hover)
vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename)
vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action)

