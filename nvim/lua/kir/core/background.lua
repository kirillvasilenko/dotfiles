-- <leader>cb or :Background [dark|light]  (no arg = toggle)

local schemes = { dark = "tokyonight-moon", light = "tokyonight-day" }

local function apply()
  vim.cmd.colorscheme(schemes[vim.o.background])
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

-- kir.core loads before lazy, so wait for tokyonight.
vim.api.nvim_create_autocmd("User", {
  pattern = "LazyDone",
  once = true,
  callback = apply,
})
