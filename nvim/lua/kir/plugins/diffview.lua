return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons" },
  opts = {},
  cmd = {
    "DiffviewOpen",
    "DiffviewClose",
    "DiffviewToggleFiles",
    "DiffviewFocusFiles",
    "DiffviewRefresh",
    "DiffviewFileHistory",
  },
  keys = {
    { "<leader>gd", "<cmd>DiffviewOpen<CR>", desc = "Open diffview" },
    { "<leader>gq", "<cmd>DiffviewClose<CR>", desc = "Close diffview" },
    { "<leader>gh", "<cmd>DiffviewFileHistory<CR>", desc = "File history (repo)" },
    { "<leader>gf", "<cmd>DiffviewFileHistory %<CR>", desc = "File history (current file)" },
  },
}
