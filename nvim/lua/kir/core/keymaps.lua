-- set leader key to space
vim.g.mapleader = " "

local keymap = vim.keymap -- for conciseness

-- General Keymaps -------------------

-- clear search highlights
keymap.set("n", "<leader>ch", ":nohl<CR>", { desc = "Clear search highlights" })

-- delete single character without copying into register
-- keymap.set("n", "x", '"_x')

-- buffer management (alternate also: Neovim default Ctrl-^)
-- Uses bufdelete.nvim so deleting a buffer keeps the window (e.g. with tree/qf open).
local function delete_buffer(buf)
  require("bufdelete").bufdelete(buf, false)
end

local function close_hidden_saved_buffers()
  local closed = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and not vim.bo[buf].modified
      and vim.bo[buf].buftype ~= "terminal" and #vim.fn.win_findbuf(buf) == 0 then
      local ok, err = pcall(vim.cmd.bdelete, { count = buf })
      if not ok then
        vim.notify(tostring(err), vim.log.levels.WARN)
      elseif not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].buflisted then
        closed = closed + 1
      end
    end
  end
  vim.notify(closed == 0 and "Nothing to close" or string.format("Closed %d buffer(s)", closed))
end

keymap.set("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })
keymap.set("n", "[b", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
keymap.set("n", "]B", "<cmd>blast<CR>", { desc = "Last buffer" })
keymap.set("n", "[B", "<cmd>bfirst<CR>", { desc = "First buffer" })
keymap.set("n", "<leader><leader>", "<cmd>buffer #<CR>", { desc = "Switch to alternate buffer" })
keymap.set("n", "<leader>bb", "<cmd>buffer #<CR>", { desc = "Switch to alternate buffer" })
keymap.set("n", "<leader>bn", "<cmd>enew<CR>", { desc = "New empty buffer" })
keymap.set("n", "<leader>bd", function()
  delete_buffer(0)
end, { desc = "Delete buffer" })
keymap.set("n", "<leader>bo", close_hidden_saved_buffers, { desc = "Close hidden saved buffers" })

-- tab management (next/prev: Neovim defaults gt / gT)
keymap.set("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "Open new tab" }) -- open new tab
keymap.set("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Open current buffer in new tab" }) --  move current buffer to new tab
keymap.set("n", "<leader>tc", "<cmd>tabclose<CR>", { desc = "Close current tab" }) -- close current tab
keymap.set("n", "<leader>to", "<cmd>tabonly<CR>", { desc = "Close other tabs" }) -- close other tabs
