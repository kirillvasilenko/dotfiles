
-- Diffview
local diffview = require("diffview")

diffview.setup({})

vim.keymap.set("n", "<leader>gd", "<cmd>DiffviewOpen<CR>")
vim.keymap.set("n", "<leader>gq", "<cmd>DiffviewClose<CR>")
vim.keymap.set("n", "<leader>gh", "<cmd>DiffviewFileHistory<CR>")
vim.keymap.set("n", "<leader>gf", "<cmd>DiffviewFileHistory %<CR>")
