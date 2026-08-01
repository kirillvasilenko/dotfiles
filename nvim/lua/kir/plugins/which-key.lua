return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  init = function()
    vim.o.timeout = true
    vim.o.timeoutlen = 500
  end,
  opts = {
    defer = function(ctx)
      -- default only defers V and CTRL-V; include v too
      return vim.tbl_contains({ "v", "V", "\22" }, ctx.mode)
    end,
  },
}