return {
  "folke/trouble.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons", "folke/todo-comments.nvim" },
  opts = {
    focus = true,
    modes = {
      -- default right-split is 30; 30 C-w-< from the editor is +30
      symbols = {
        -- mode default is focus=false (sidebar); gO should land in the list
        focus = true,
        win = { position = "right", size = 60 },
      },
    },
  },
  cmd = "Trouble",
  keys = {
    { "<leader>xw", "<cmd>Trouble diagnostics toggle<CR>", desc = "Toggle trouble workspace diagnostics" },
    { "<leader>xb", "<cmd>Trouble diagnostics toggle filter.buf=0<CR>", desc = "Toggle trouble buffer diagnostics" },
    { "<leader>xq", "<cmd>Trouble qflist toggle<CR>", desc = "Toggle trouble quickfix list" },
    { "<leader>xl", "<cmd>Trouble loclist toggle<CR>", desc = "Toggle trouble location list" },
    { "<leader>xt", "<cmd>Trouble todo toggle<CR>", desc = "Toggle todos in trouble" },
  },
}