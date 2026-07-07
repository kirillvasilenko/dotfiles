
-- Gitsigns
require("gitsigns").setup({
  attach_to_untracked = true,
  on_attach = function(bufnr)
    local gs = require("gitsigns")

    vim.keymap.set("n", "]h", gs.next_hunk, { buffer = bufnr })
    vim.keymap.set("n", "[h", gs.prev_hunk, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hs", gs.stage_hunk, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hr", gs.reset_hunk, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hp", gs.preview_hunk, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hl", gs.preview_hunk_inline, { buffer = bufnr })
    vim.keymap.set("n", "<leader>ht", gs.toggle_linehl, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hS", gs.stage_buffer, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hR", gs.reset_buffer, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hB", function()
      gs.blame_line({ full = true })
    end, { buffer = bufnr })
    vim.keymap.set("n", "<leader>hb", gs.toggle_current_line_blame, { buffer = bufnr })
    vim.keymap.set({ "o", "x" }, "ih", gs.select_hunk, { buffer = bufnr })
  end,
})
