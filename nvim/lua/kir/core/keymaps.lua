-- set leader key to space
vim.g.mapleader = " "

local keymap = vim.keymap -- for conciseness

-- General Keymaps -------------------

-- clear search highlights
keymap.set("n", "<leader>ch", ":nohl<CR>", { desc = "Clear search highlights" })

-- delete single character without copying into register
-- keymap.set("n", "x", '"_x')

-- tab management (next/prev: Neovim defaults gt / gT)
keymap.set("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "Open new tab" }) -- open new tab
keymap.set("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Open current buffer in new tab" }) --  move current buffer to new tab
keymap.set("n", "<leader>tc", "<cmd>tabclose<CR>", { desc = "Close current tab" }) -- close current tab
keymap.set("n", "<leader>to", "<cmd>tabonly<CR>", { desc = "Close other tabs" }) -- close other tabs
