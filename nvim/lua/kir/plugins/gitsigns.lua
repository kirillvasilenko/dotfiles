return {
  "lewis6991/gitsigns.nvim",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local gs = require("gitsigns")
    local review_mode = false

    gs.setup({
      attach_to_untracked = true,
      on_attach = function(bufnr)
        local function map(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
        end

        map("n", "]h", function()
          gs.nav_hunk("next")
        end, "Next hunk")
        map("n", "[h", function()
          gs.nav_hunk("prev")
        end, "Previous hunk")

        map("n", "<leader>hs", gs.stage_hunk, "Stage hunk")
        map("n", "<leader>hu", gs.undo_stage_hunk, "Undo stage hunk")
        map("n", "<leader>hr", gs.reset_hunk, "Reset hunk")
        map("n", "<leader>hS", gs.stage_buffer, "Stage buffer")
        map("n", "<leader>hR", gs.reset_buffer, "Reset buffer")
        map("v", "<leader>hs", function()
          gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
        end, "Stage hunk")
        map("v", "<leader>hr", function()
          gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
        end, "Reset hunk")

        map("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
        map("n", "<leader>hl", gs.toggle_linehl, "Toggle line highlight")
        map("n", "<leader>hw", gs.toggle_word_diff, "Toggle word diff")
        map("n", "<leader>ht", function()
          review_mode = not review_mode
          gs.toggle_linehl(review_mode)
          gs.toggle_word_diff(review_mode)
          require("gitsigns.config").config.show_deleted = review_mode
          gs.refresh()
        end, "Toggle review mode")

        map("n", "<leader>hb", function()
          gs.blame_line({ full = true })
        end, "Blame line")
        map("n", "<leader>hB", gs.toggle_current_line_blame, "Toggle line blame")

        map("n", "<leader>hd", gs.diffthis, "Diff this")
        map("n", "<leader>hD", function()
          gs.diffthis("~")
        end, "Diff this ~")

        map({ "o", "x" }, "ih", gs.select_hunk, "Select hunk")
      end,
    })
  end,
}
