local current_colorscheme = "default"
-- local current_colorscheme = "tokyonight"
return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("tokyonight").setup({
        style = "moon",
        light_style = "day",
        -- Lowers the total background light output significantly
        day_brightness = 0.2, 
      })
      vim.cmd.colorscheme(current_colorscheme)

      -- Do NOT set 'background' yourself. Neovim 0.11+ tracks it from the
      -- terminal via OSC 11, and explicitly setting it disables that.

      -- When 'background' flips, Everforest must be reloaded to pick the
      -- matching light/dark palette. Neovim also reloads the colorscheme on
      -- 'background' change; this keeps it reliable for schemes that need it.
      vim.api.nvim_create_autocmd("OptionSet", {
        pattern = "background",
        callback = function()
          vim.cmd.colorscheme(current_colorscheme)
        end,
      })

      -- Many terminals (notably Warp) follow the OS theme visually but do not
      -- implement DEC mode 2031, so Neovim never gets a "theme changed"
      -- notification and won't re-query on its own. Periodically ask for the
      -- current background color; Neovim's built-in TermResponse handler
      -- updates 'background' when the luminance changes.
      local timer = assert(vim.uv.new_timer())
      timer:start(0, 2000, function()
        vim.schedule(function()
          pcall(vim.api.nvim_ui_send, "\027]11;?\007")
        end)
      end)

      vim.api.nvim_create_autocmd("VimLeavePre", {
        once = true,
        callback = function()
          if timer:is_active() then
            timer:stop()
          end
          if not timer:is_closing() then
            timer:close()
          end
        end,
      })
    end,
  },
}
