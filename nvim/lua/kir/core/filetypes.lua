-- Treat .h headers as C++ (affects treesitter, filetype-gated plugins, etc.).
vim.filetype.add({
  extension = {
    h = "cpp",
  },
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.bo.tabstop = 2
    vim.bo.shiftwidth = 2
    vim.bo.expandtab = true
  end,
})
