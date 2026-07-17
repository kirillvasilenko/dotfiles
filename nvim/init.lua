-- Leader key
vim.g.mapleader = " "

require("config/options")
require("config/keymap")
require("config/cursorlink")

-- Bootstrap lazy.nvim (auto install)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Setup plugins
require("lazy").setup({
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-live-grep-args.nvim",
    },
  },
  {
    "neovim/nvim-lspconfig",
  },
  -- code completion
  {
    "hrsh7th/nvim-cmp",
    dependencies = { "hrsh7th/cmp-nvim-lsp" },
  },
  -- AI completion
  {
    "supermaven-inc/supermaven-nvim",
  },
  {
    "p00f/clangd_extensions.nvim",
    dependencies = { "neovim/nvim-lspconfig" },
  },
  {
    "sindrets/diffview.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
    },
  },
  {
    "lewis6991/gitsigns.nvim",
  },
  -- Markdown syntax highlighting (treesitter)
  {
    "nvim-treesitter/nvim-treesitter",
    -- The main branch does not support lazy-loading.
    lazy = false,
    build = ":TSUpdate",
  },
  -- Markdown preview with mermaid support (rendered in browser via forwarded port)
  {
    "iamcco/markdown-preview.nvim",
    ft = { "markdown" },
    -- --no-package-lock keeps the plugin's git tree clean so `:Lazy sync` won't refuse to update (npm would otherwise rewrite the tracked yarn.lock).
    build = "cd app && npm install --no-package-lock",
  },
})

require("config/telescope")
require("config/supermaven")
require("config/cmp")
require("config/lsp")
require("config/clangd")
require("config/python")
require("config/diffview")
require("config/gitsigns")
require("config/treesitter")
require("config/markdown")
