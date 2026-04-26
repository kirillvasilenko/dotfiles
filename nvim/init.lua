-- Leader key
vim.g.mapleader = " "

require("config/options")
require("config/keymap")

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
    dependencies = { "nvim-lua/plenary.nvim" }
  },
  {
    "neovim/nvim-lspconfig",
  },
  -- code completion
  {
    "hrsh7th/nvim-cmp",
    dependencies = { "hrsh7th/cmp-nvim-lsp" },
  },
  {
    "p00f/clangd_extensions.nvim",
    dependencies = { "neovim/nvim-lspconfig" },
  }
})

require("config/telescope")
require("config/cmp")
require("config/lsp")
require("config/clangd")
