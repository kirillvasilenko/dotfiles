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
    -- Prose lines stay long in the file (hard wraps break Obsidian/GitHub
    -- rendering), so wrap them visually instead.
    vim.wo.wrap = true
    vim.wo.linebreak = true -- break at word boundaries, not mid-word
    vim.wo.breakindent = true -- keep list/quote indentation on wrapped lines
    -- Move by visual line while wrapped, unless a count is given (3j etc.).
    vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { buffer = true, expr = true })
    vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { buffer = true, expr = true })
  end,
})
