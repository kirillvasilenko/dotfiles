-- <leader>cb or :Background [dark|light]  (no arg = toggle)

local schemes = { dark = "tokyonight-moon", light = "tokyonight-day" }

local function apply()
  local name = schemes[vim.o.background]
  if not name then
    return
  end
  vim.cmd.colorscheme(name)
  pcall(function()
    require("lualine").refresh({ place = { "statusline" } })
  end)
end

local function set_bg(want)
  if not want or want == "" or want == "toggle" then
    want = vim.o.background == "dark" and "light" or "dark"
  end
  vim.o.background = want
  apply()
end

vim.api.nvim_create_user_command("Background", function(opts)
  set_bg(opts.args)
end, { nargs = "?" })

vim.keymap.set("n", "<leader>cb", function()
  set_bg()
end, { desc = "Toggle light/dark theme" })
