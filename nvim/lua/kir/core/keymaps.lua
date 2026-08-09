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

-- Close other listed buffers that are unmodified; leave dirty ones for manual save/discard.
local function buffer_only_soft()
  local current = vim.api.nvim_get_current_buf()
  local closed, kept = 0, 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= current and vim.bo[buf].buflisted then
      if vim.bo[buf].modified then
        kept = kept + 1
      elseif pcall(delete_buffer, buf) then
        closed = closed + 1
      end
    end
  end
  if kept > 0 then
    vim.notify(
      string.format("Closed %d buffer(s), kept %d modified", closed, kept),
      vim.log.levels.WARN
    )
  else
    vim.notify(string.format("Closed %d buffer(s)", closed), vim.log.levels.INFO)
  end
end

keymap.set("n", "]b", "<cmd>bnext<CR>", { desc = "Next buffer" })
keymap.set("n", "[b", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
keymap.set("n", "]B", "<cmd>blast<CR>", { desc = "Last buffer" })
keymap.set("n", "[B", "<cmd>bfirst<CR>", { desc = "First buffer" })
keymap.set("n", "<leader>bb", "<cmd>buffer #<CR>", { desc = "Switch to alternate buffer" })
keymap.set("n", "<leader>bn", "<cmd>enew<CR>", { desc = "New empty buffer" })
keymap.set("n", "<leader>bd", function()
  delete_buffer(0)
end, { desc = "Delete buffer" })
keymap.set("n", "<leader>bo", buffer_only_soft, { desc = "Delete other unmodified buffers" })

-- tab management (next/prev: Neovim defaults gt / gT)
keymap.set("n", "<leader>tn", "<cmd>tabnew<CR>", { desc = "Open new tab" }) -- open new tab
keymap.set("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Open current buffer in new tab" }) --  move current buffer to new tab
keymap.set("n", "<leader>tc", "<cmd>tabclose<CR>", { desc = "Close current tab" }) -- close current tab
keymap.set("n", "<leader>to", "<cmd>tabonly<CR>", { desc = "Close other tabs" }) -- close other tabs
