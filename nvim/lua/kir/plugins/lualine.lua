return {
  "nvim-lualine/lualine.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    local lualine = require("lualine")
    local lazy_status = require("lazy.status") -- to configure lazy pending updates count

    -- hide -- INSERT -- / -- VISUAL --; lualine shows mode
    vim.opt.showmode = false

    -- configure lualine with modified theme
    lualine.setup({
      sections = {
        lualine_x = {
          {
            lazy_status.updates,
            cond = lazy_status.has_updates,
          },
          { "encoding" },
          { "fileformat" },
          { "filetype" },
        },
      },
    })

    -- force statusline refresh on mode change (avoids stale NORMAL in visual)
    vim.api.nvim_create_autocmd("ModeChanged", {
      pattern = "*:*",
      callback = function()
        lualine.refresh({ place = { "statusline" } })
      end,
    })
  end,
}