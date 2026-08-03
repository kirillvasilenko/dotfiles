-- Quickfix list helpers and <leader>q… keymaps.
-- Entry nav (defaults):  [q ]q  [Q ]Q
-- List stack nav:        <leader>[q <leader>]q  <leader>[Q <leader>]Q

local keymap = vim.keymap

---@param qf table getqflist({ all = true }) result
---@return table[]
local function items_with_filenames(qf)
  local items = {}
  for _, item in ipairs(qf.items or {}) do
    local copy = vim.deepcopy(item)
    if copy.bufnr and copy.bufnr > 0 and vim.api.nvim_buf_is_valid(copy.bufnr) then
      copy.filename = vim.api.nvim_buf_get_name(copy.bufnr)
      copy.bufnr = nil
    end
    items[#items + 1] = copy
  end
  return items
end

--- Rebuild the entire qflist stack from a list of getqflist({all=true}) snapshots.
---@param lists table[]
local function rebuild_qflist_stack(lists)
  vim.fn.setqflist({}, "f")
  for _, qf in ipairs(lists) do
    vim.fn.setqflist({}, " ", {
      title = qf.title,
      items = items_with_filenames(qf),
      context = qf.context,
    })
  end
end

local function delete_qf_entry()
  local wininfo = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  local in_list_win = wininfo.quickfix == 1
  local is_loclist = wininfo.loclist == 1

  local list, idx
  if is_loclist then
    list = vim.fn.getloclist(0)
    idx = in_list_win and vim.fn.line(".") or vim.fn.getloclist(0, { idx = 0 }).idx
  else
    list = vim.fn.getqflist()
    idx = in_list_win and vim.fn.line(".") or vim.fn.getqflist({ idx = 0 }).idx
  end

  if not idx or idx < 1 or idx > #list then
    return
  end

  table.remove(list, idx)

  if is_loclist then
    vim.fn.setloclist(0, {}, "r", { items = list })
  else
    vim.fn.setqflist({}, "r", { items = list })
  end

  if in_list_win then
    local new_idx = math.min(idx, #list)
    if new_idx > 0 then
      vim.api.nvim_win_set_cursor(0, { new_idx, 0 })
    end
  end
end

local function add_current(note)
  vim.fn.setqflist({}, "a", {
    items = {
      {
        bufnr = vim.api.nvim_get_current_buf(),
        lnum = vim.fn.line("."),
        col = vim.fn.col("."),
        text = note or vim.fn.getline("."),
      },
    },
  })
end

local function add_current_plain()
  add_current(vim.fn.getline("."))
end

local function add_current_with_note()
  local note = vim.fn.input("qf note: ")
  if note == "" then
    return
  end
  add_current(note)
end

-- Non-jumpable section marker (skipped by :cnext / ]q).
local function add_separator()
  local label = vim.fn.input("qf separator: ")
  if label == "" then
    return
  end
  vim.fn.setqflist({}, "a", {
    items = {
      { text = "──── " .. label .. " ────", valid = 0 },
    },
  })
end

-- Empty the current list but leave it on the stack.
local function clear_qflist()
  vim.fn.setqflist({}, "r")
end

-- Remove the current list from the stack entirely.
local function delete_qflist()
  local current_nr = vim.fn.getqflist({ nr = 0 }).nr
  local total = vim.fn.getqflist({ nr = "$" }).nr

  if total == 0 then
    return
  end

  if total == 1 then
    vim.fn.setqflist({}, "f")
    vim.cmd("cclose")
    return
  end

  local kept = {}
  for i = 1, total do
    if i ~= current_nr then
      kept[#kept + 1] = vim.fn.getqflist({ nr = i, all = true })
    end
  end

  rebuild_qflist_stack(kept)

  -- Stay on a sensible neighbor: previous list, or first if we deleted #1.
  local target = math.max(1, current_nr - 1)
  vim.cmd(target .. "chistory")
end

-- Remove every list from the stack.
local function delete_all_qflists()
  vim.fn.setqflist({}, "f")
  vim.cmd("cclose")
end

-- Rename the current list (title shown in :chistory / qf window).
local function rename_qflist()
  local total = vim.fn.getqflist({ nr = "$" }).nr
  if total == 0 then
    vim.notify("No quickfix list to rename", vim.log.levels.WARN)
    return
  end

  local current = vim.fn.getqflist({ title = 1 }).title or ""
  local title = vim.fn.input("qf list title: ", current)
  if title == "" then
    return
  end
  vim.fn.setqflist({}, "a", { title = title })
end

-- Move the current list to the newest end of the stack ("top").
local function move_qflist_to_top()
  local current_nr = vim.fn.getqflist({ nr = 0 }).nr
  local total = vim.fn.getqflist({ nr = "$" }).nr

  if total <= 1 or current_nr == total then
    return
  end

  local current = vim.fn.getqflist({ nr = current_nr, all = true })
  local lists = {}
  for i = 1, total do
    if i ~= current_nr then
      lists[#lists + 1] = vim.fn.getqflist({ nr = i, all = true })
    end
  end
  lists[#lists + 1] = current

  rebuild_qflist_stack(lists)
  -- Last created list is current.
end

local function goto_oldest_qflist()
  local total = vim.fn.getqflist({ nr = "$" }).nr
  if total > 0 then
    vim.cmd("1chistory")
  end
end

local function goto_newest_qflist()
  local total = vim.fn.getqflist({ nr = "$" }).nr
  if total > 0 then
    vim.cmd(total .. "chistory")
  end
end

-- Create a new empty list on the stack (with a title/comment).
local function new_qflist()
  local title = vim.fn.input("qf list title: ")
  if title == "" then
    title = "investigation"
  end
  vim.fn.setqflist({}, " ", { title = title, items = {} })
end

-- Stock Neovim leaves the qf buffer nomodifiable, so plain dd does nothing.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "qf",
  callback = function(ev)
    keymap.set("n", "dd", delete_qf_entry, {
      buffer = ev.buf,
      desc = "Delete quickfix/location list entry",
    })
  end,
})

-- Window
keymap.set("n", "<leader>qo", "<cmd>copen<CR>", { desc = "Quickfix open" })
keymap.set("n", "<leader>qc", "<cmd>cclose<CR>", { desc = "Quickfix close" })

-- List stack (parallel to [q/]q/[Q/]Q, but with leader)
keymap.set("n", "<leader>qh", "<cmd>chistory<CR>", { desc = "Quickfix history" })
keymap.set("n", "<leader>[q", "<cmd>colder<CR>", { desc = "Quickfix older list" })
keymap.set("n", "<leader>]q", "<cmd>cnewer<CR>", { desc = "Quickfix newer list" })
keymap.set("n", "<leader>[Q", goto_oldest_qflist, { desc = "Quickfix oldest list" })
keymap.set("n", "<leader>]Q", goto_newest_qflist, { desc = "Quickfix newest list" })

-- Edit list / stack
keymap.set("n", "<leader>qn", new_qflist, { desc = "Quickfix new list (title)" })
keymap.set("n", "<leader>qr", rename_qflist, { desc = "Quickfix rename current list" })
keymap.set("n", "<leader>qa", add_current_plain, { desc = "Quickfix add current line" })
keymap.set("n", "<leader>qA", add_current_with_note, { desc = "Quickfix add current line with note" })
keymap.set("n", "<leader>qs", add_separator, { desc = "Quickfix add separator" })
keymap.set("n", "<leader>qd", delete_qf_entry, { desc = "Quickfix delete current entry" })
keymap.set("n", "<leader>qD", clear_qflist, { desc = "Quickfix delete all entries in current list" })
keymap.set("n", "<leader>qx", delete_qflist, { desc = "Quickfix delete current list" })
keymap.set("n", "<leader>qX", delete_all_qflists, { desc = "Quickfix delete all lists" })
keymap.set("n", "<leader>qt", move_qflist_to_top, { desc = "Quickfix move current list to top" })
