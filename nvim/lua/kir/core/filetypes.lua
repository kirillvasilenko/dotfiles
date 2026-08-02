-- Treat .h headers as C++ (affects treesitter, filetype-gated plugins, etc.).
vim.filetype.add({
  extension = {
    h = "cpp",
  },
})
