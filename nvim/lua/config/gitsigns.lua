
-- Gitsigns
local review_mode = false
require("gitsigns").setup({
  attach_to_untracked = true,
  show_deleted = review_mode,
  on_attach = function(bufnr)
    local gs = require("gitsigns")

    vim.keymap.set("n", "]h", gs.next_hunk, { buffer = bufnr })
    vim.keymap.set("n", "[h", gs.prev_hunk, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hs", gs.stage_hunk, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hr", gs.reset_hunk, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hp", gs.preview_hunk, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hl", gs.toggle_linehl, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hw", gs.toggle_word_diff, { buffer = bufnr })
    vim.keymap.set("n", "<leader>ht", function()
      review_mode = not review_mode
      local config = require("gitsigns.config").config
      config.show_deleted = review_mode
      config.linehl = review_mode
      config.word_diff = review_mode
      gs.refresh()
    end, { desc = "Toggle review mode" })
    vim.keymap.set("n", "<leader>hS", gs.stage_buffer, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hR", gs.reset_buffer, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hB", function()
      gs.blame_line({ full = true })
    end, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hb", gs.toggle_current_line_blame, { buffer = bufnr })
    vim.keymap.set({ "o", "x" }, "ih", gs.select_hunk, { buffer = bufnr })
  end,
})
