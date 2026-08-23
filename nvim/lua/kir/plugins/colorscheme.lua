return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("tokyonight").setup({
        style = "moon",
        light_style = "day",
        day_brightness = 0.2,
      })
      -- Apply here (priority 1000) so lualine/bufferline setup on the real palette.
      local schemes = { dark = "tokyonight-moon", light = "tokyonight-day" }
      vim.cmd.colorscheme(schemes[vim.o.background] or "tokyonight-moon")
    end,
  },
}
