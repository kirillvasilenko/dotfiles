return {
  "nvim-treesitter/nvim-treesitter",
  lazy = false, -- upstream: do not lazy-load
  build = ":TSUpdate",
  config = function()
    -- async; no-op once parsers are already installed
    require("nvim-treesitter").install({
      "json",
      "javascript",
      "typescript",
      "tsx",
      "yaml",
      "html",
      "css",
      "prisma",
      "markdown",
      "markdown_inline",
      "graphql",
      "bash",
      "lua",
      "vim",
      "dockerfile",
      "gitignore",
      "query",
      "vimdoc",
      "c",
      "cpp",
      "python",
      "sql",
    })

    -- highlight / indent are not modules on main; enable them per buffer
    vim.api.nvim_create_autocmd("FileType", {
      callback = function(args)
        pcall(vim.treesitter.start, args.buf)
        vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
      end,
    })
  end,
}
