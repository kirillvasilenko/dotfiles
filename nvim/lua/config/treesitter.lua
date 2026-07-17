-- nvim-treesitter (main branch API; requires Neovim 0.12+ and the tree-sitter CLI).

-- Parsers to install. Runs asynchronously and is a no-op once installed.
require("nvim-treesitter").install({
  "markdown",
  "markdown_inline",
  "mermaid",
  "c",
  "cpp",
  "python",
  "lua",
})

-- On the main branch, highlighting is provided by Neovim core and enabled per
-- buffer. Enable it for any filetype that has a parser installed; pcall guards
-- filetypes without a parser (and the first launch before install() finishes).
vim.api.nvim_create_autocmd("FileType", {
  callback = function(args)
    pcall(vim.treesitter.start, args.buf)
  end,
})
