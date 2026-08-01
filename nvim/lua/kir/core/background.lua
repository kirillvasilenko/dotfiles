-- Sync colorscheme with the local terminal's light/dark via OSC 11.
-- Don't set 'background' yourself: Neovim 0.11+ derives it from the terminal,
-- and an explicit set disables that.
--
-- Warp over SSH answers OSC 11 but has no DEC 2031 theme-change push, so we
-- re-query on focus + a short poll. Neovim updates 'background'; we only
-- reload when it actually flips.
--
-- Starts on LazyDone so colorscheme plugins from lazy.nvim are available
-- (this module is required from kir.core before lazy.setup).

-- local colorscheme = "default"
local colorscheme = "tokyonight"

-- Optional light/dark variants for schemes that ship both.
local variants = {
  tokyonight = { light = "tokyonight-day", dark = "tokyonight-moon" },
}

local last_bg ---@type string?

local function name_for(bg)
  local variant = variants[colorscheme]
  if variant then
    return bg == "light" and variant.light or variant.dark
  end
  return colorscheme
end

local function refresh_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype ~= "" then
      pcall(vim.treesitter.stop, buf)
      pcall(vim.treesitter.start, buf)
    end
  end
  pcall(function()
    require("ibl").refresh_all()
  end)
  vim.cmd.redraw({ bang = true })
end

---@param refresh boolean?
local function apply(refresh)
  local bg = vim.o.background
  local name = name_for(bg)
  if bg == last_bg and vim.g.colors_name == name then
    return
  end
  last_bg = bg
  vim.cmd.colorscheme(name)
  if refresh then
    -- `hi clear` during :colorscheme can leave TS/ibl stale until reload.
    vim.schedule(refresh_buffers)
  end
end

local function start()
  apply()

  vim.api.nvim_create_autocmd("OptionSet", {
    pattern = "background",
    callback = function()
      vim.schedule(function()
        apply(true)
      end)
    end,
  })

  local function query()
    pcall(vim.api.nvim_ui_send, "\027]11;?\007")
  end

  vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, { callback = query })

  local timer = assert(vim.uv.new_timer())
  timer:start(1000, 2000, vim.schedule_wrap(query))
  vim.api.nvim_create_autocmd("VimLeavePre", {
    once = true,
    callback = function()
      timer:stop()
      if not timer:is_closing() then
        timer:close()
      end
    end,
  })
end

vim.api.nvim_create_autocmd("User", {
  pattern = "LazyDone",
  once = true,
  callback = start,
})
