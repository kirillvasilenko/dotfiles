-- Copy a "Cursor style" reference link (@path:start-end) for the current
-- selection / line / motion, so it can be pasted into the Cursor chat.

local function repo_root(path)
  -- nvim >= 0.10
  if vim.fs.root then
    local root = vim.fs.root(path, ".git")
    if root then
      return root
    end
  end
  -- fallback: walk upward looking for a .git entry
  local dir = vim.fs.dirname(path)
  local git = vim.fs.find(".git", { path = dir, upward = true })[1]
  if git then
    return vim.fs.dirname(git)
  end
  return nil
end

local function build_link(start_line, end_line)
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname == "" then
    vim.notify("cursorlink: current buffer has no file", vim.log.levels.WARN)
    return nil
  end

  local abs = vim.fn.fnamemodify(bufname, ":p")
  local root = repo_root(abs)
  local rel
  if root then
    rel = abs:sub(#root + 2) -- strip "<root>/"
  else
    rel = vim.fn.fnamemodify(abs, ":.") -- relative to cwd as a fallback
  end

  if start_line == end_line then
    return string.format("@%s:%d", rel, start_line)
  end
  return string.format("@%s:%d-%d", rel, start_line, end_line)
end

local function copy(start_line, end_line)
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  local link = build_link(start_line, end_line)
  if not link then
    return
  end
  vim.fn.setreg("+", link)
  vim.fn.setreg('"', link)
  vim.notify("Copied: " .. link)
end

-- Called by 'operatorfunc' after a motion (g@). Uses the [ and ] marks.
function _G.__cursorlink_operator()
  local start_line = vim.api.nvim_buf_get_mark(0, "[")[1]
  local end_line = vim.api.nvim_buf_get_mark(0, "]")[1]
  copy(start_line, end_line)
end

-- Operator: yc + motion  (e.g. ycap, yc})
-- Safe to overload: `yc<motion>` is unused in vanilla Vim (`c` is not a motion).
vim.keymap.set("n", "yc", function()
  vim.o.operatorfunc = "v:lua.__cursorlink_operator"
  return "g@"
end, { expr = true, desc = "Yank Cursor link (operator)" })

-- Current line: ycc
vim.keymap.set("n", "ycc", function()
  vim.o.operatorfunc = "v:lua.__cursorlink_operator"
  return "g@_"
end, { expr = true, desc = "Yank Cursor link (current line)" })

-- Visual selection: yc
vim.keymap.set("x", "yc", function()
  copy(vim.fn.line("v"), vim.fn.line("."))
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "n", false)
end, { desc = "Yank Cursor link (selection)" })
