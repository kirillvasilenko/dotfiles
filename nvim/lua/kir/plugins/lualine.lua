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
        lualine_c = {
          { "filename", path = 1 }, -- relative path
        },
        lualine_x = {
          {
            lazy_status.updates,
            cond = lazy_status.has_updates,
          },
          {
            -- green ● ready; orange ● indexing (calls work, may be partial);
            -- orange ○ parsing (calls rejected)
            function()
              local st = require("kir.lsp.clangd_ready").status()
              if st == "ready" or st == "indexing" then
                return "● LSP"
              end
              if st == "parsing" then
                return "○ LSP"
              end
              return ""
            end,
            color = function()
              local st = require("kir.lsp.clangd_ready").status()
              return st == "ready" and "DiagnosticOk" or "DiagnosticWarn"
            end,
            cond = function()
              return require("kir.lsp.clangd_ready").status() ~= nil
            end,
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

    vim.api.nvim_create_autocmd("User", {
      pattern = "KirClangdReady",
      callback = function()
        lualine.refresh({ place = { "statusline" } })
      end,
    })
  end,
}