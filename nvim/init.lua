-- Line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Indentation
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- UI
vim.opt.termguicolors = true
vim.opt.scrolloff = 8

-- Leader key
vim.g.mapleader = " "

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
  }
})

-- Telescope
local builtin = require("telescope.builtin")

-- In the search window you can ctrl+v/x/t - open the file in a vertical/horisontal split/new tab
vim.keymap.set("n", "<leader>ff", builtin.find_files)
vim.keymap.set("n", "<leader>fb", builtin.buffers)
vim.keymap.set("n", "<leader>fr", builtin.resume)
-- find the word under the cursor
vim.keymap.set("n", "<leader>fw", builtin.grep_string)
vim.keymap.set("n", "<leader>fg", builtin.live_grep)
-- find all
vim.keymap.set("n", "<leader>fa", function()
  builtin.live_grep({
    additional_args = function()
      return { "--hidden" }
    end,
    prompt_title = "Live Grep Hidden",
  })
end)
-- find in the current folder
vim.keymap.set("n", "<leader>fd", function()
  builtin.live_grep({
    cwd = vim.fn.expand("%:p:h"),
    prompt_title = "Live Grep Current Dir",
  })
end)
vim.keymap.set("n", "<leader>/", builtin.current_buffer_fuzzy_find)

vimgrep_arguments = {
  "rg",
  "--color=never",
  "--no-heading",
  "--with-filename",
  "--line-number",
  "--column",
  "--smart-case",
}
