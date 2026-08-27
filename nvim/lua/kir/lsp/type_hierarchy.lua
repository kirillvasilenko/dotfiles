-- Type hierarchy tree (clangd_extensions.nvim's ClangdTypeHierarchy, with
-- qualified names + filenames, and gd keyed by line so same-named types
-- do not collide).

local api = vim.api

local M = {}
M.type_to_location = {}
M.offset_encoding = {}

local augroup = api.nvim_create_augroup("KirClangdTypeHierarchy", { clear = true })

local function kind_name(kind)
  return vim.lsp.protocol.SymbolKind[kind] or "?"
end

-- clangd: AST items set detail to the qualified name; index items set it to
-- the enclosing scope only (no trailing name).
local function qualified_name(node)
  local name = node.name or "?"
  local detail = node.detail
  if type(detail) ~= "string" or detail == "" or detail == name then
    return name
  end
  -- Require "::name" so "MyHandler" is not treated as qualified "Handler".
  if detail:sub(-(#name + 2)) == "::" .. name then
    return detail
  end
  return detail .. "::" .. name
end

local function file_path(node)
  if not node.uri then
    return nil
  end
  local ok, fname = pcall(vim.uri_to_fname, node.uri)
  if not ok or not fname or fname == "" then
    return nil
  end

  local root = vim.fs.root(fname, { ".git" })
  if root then
    local rel = vim.fs.relpath and vim.fs.relpath(root, fname)
    if type(rel) == "string" and rel ~= "" then
      return rel
    end
    if fname:sub(1, #root) == root then
      return fname:sub(#root + 1):gsub("^/", "")
    end
  end

  return fname
end

local function qualified_from_symbol_info(info)
  if not info then
    return nil
  end
  local name = info.name
  local container = info.containerName
  if type(name) ~= "string" or name == "" then
    return nil
  end
  if type(container) ~= "string" or container == "" then
    return name
  end
  if container:sub(-2) == "::" then
    return container .. name
  end
  return container .. "::" .. name
end

local function apply_root_name(root, info)
  local from_info = qualified_from_symbol_info(info)
  if not from_info then
    return
  end
  if #from_info > #qualified_name(root) then
    root.detail = from_info
  end
end

local function sorted_nodes(nodes)
  local copy = vim.list_extend({}, nodes)
  table.sort(copy, function(a, b)
    local qa, qb = qualified_name(a), qualified_name(b)
    if qa ~= qb then
      return qa < qb
    end
    return (file_path(a) or "") < (file_path(b) or "")
  end)
  return copy
end

local function visit_key(node)
  -- Location only: the same type can appear with and without `data`, which
  -- would look like two nodes and recurse until the stack blows.
  local range = node.selectionRange or node.range
  local start = range and range.start
  return table.concat({
    node.uri or "",
    node.name or "",
    start and start.line or 0,
    start and start.character or 0,
  }, "\0")
end

local function format_tree(node, visited, result, padding, type_to_location)
  visited[visit_key(node)] = true

  local location = { uri = node.uri, range = node.selectionRange or node.range }
  table.insert(result, padding .. (" • %s: %s"):format(qualified_name(node), kind_name(node.kind)))
  type_to_location[#result] = location
  local path = file_path(node)
  if path then
    table.insert(result, padding .. "   " .. path)
    type_to_location[#result] = location
  end

  if type(node.parents) == "table" and #node.parents > 0 then
    table.insert(result, padding .. "   Parents:")
    for _, parent in ipairs(sorted_nodes(node.parents)) do
      if type(parent) == "table" and not visited[visit_key(parent)] then
        format_tree(parent, visited, result, padding .. "   ", type_to_location)
      end
    end
  end

  if type(node.children) == "table" and #node.children > 0 then
    table.insert(result, padding .. "   Children:")
    for _, child in ipairs(sorted_nodes(node.children)) do
      if type(child) == "table" and not visited[visit_key(child)] then
        format_tree(child, visited, result, padding .. "   ", type_to_location)
      end
    end
  end

  return result
end

--- Prefer the editor window we split from. After the first gd that window
--- usually shows a different file; still reuse it. Split only if no other
--- normal window is left in this tab.
local function pick_jump_win(hier_win, source_win, source_buf)
  if api.nvim_win_is_valid(source_win) and source_win ~= hier_win then
    return source_win
  end
  local found = vim.fn.win_findbuf(source_buf)[1]
  if found and found ~= 0 and found ~= hier_win then
    return found
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if w ~= hier_win then
      local b = api.nvim_win_get_buf(w)
      if vim.bo[b].buftype == "" then
        return w
      end
    end
  end
  return nil
end

local function jump_from(bufnr, target, client_id)
  local line = api.nvim_win_get_cursor(0)[1]
  local location = M.type_to_location[bufnr] and M.type_to_location[bufnr][line]
  if not location or not location.uri then
    return
  end
  local range = location.range
  if type(range) ~= "table" or type(range.start) ~= "table" then
    return
  end
  local hier_win = api.nvim_get_current_win()
  local win = pick_jump_win(hier_win, target.win, target.buf)
  if win then
    api.nvim_set_current_win(win)
  else
    -- splitbelow would put code under the hierarchy; keep code on top.
    vim.cmd("aboveleft split")
    if api.nvim_win_is_valid(hier_win) then
      api.nvim_win_set_height(hier_win, math.min(api.nvim_buf_line_count(bufnr), 20))
    end
  end
  vim.lsp.util.show_document(
    location,
    M.offset_encoding[client_id] or "utf-16",
    { focus = true }
  )
  -- Next gd should land in the same window, even if this jump replaced the buf.
  target.win = api.nvim_get_current_win()
  target.buf = api.nvim_get_current_buf()
end

---@param result table clangd TypeHierarchyItem or a list of them
local function root_item(result)
  if result.name then
    return result
  end
  if result[1] and result[1].name then
    return result[1]
  end
  return nil
end

local function render_tree(root, client_id, source_win, source_buf)
  local client = vim.lsp.get_clients({ id = client_id })[1]
  if client then
    M.offset_encoding[client_id] = client.offset_encoding
  end
  -- Open next to the file we invoked from, not whatever window is current
  -- by the time clangd answers.
  if api.nvim_win_is_valid(source_win) then
    api.nvim_set_current_win(source_win)
  end
  -- :split with no name reuses the source buffer. The plugin uses
  -- :split <name> to get a new buffer; do the same with an explicit scratch.
  vim.cmd.split()
  local win = api.nvim_get_current_win()
  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(win, bufnr)
  local name = qualified_name(root) .. " [type hierarchy]"
  if vim.fn.bufexists(name) == 1 then
    name = name .. " " .. bufnr
  end
  pcall(api.nvim_buf_set_name, bufnr, name)
  M.type_to_location[bufnr] = {}

  local lines = format_tree(root, {}, {}, "", M.type_to_location[bufnr])
  api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

  local function buf_opt(name_, value)
    api.nvim_set_option_value(name_, value, { buf = bufnr })
  end
  local function win_opt(name_, value)
    api.nvim_set_option_value(name_, value, { win = win })
  end
  buf_opt("modifiable", false)
  buf_opt("filetype", "ClangdTypeHierarchy")
  buf_opt("buftype", "nofile")
  buf_opt("bufhidden", "wipe")
  buf_opt("buflisted", false)
  win_opt("number", false)
  win_opt("relativenumber", false)
  win_opt("spell", false)
  win_opt("cursorline", true)
  api.nvim_win_set_height(win, math.min(#lines, 20))

  pcall(api.nvim_buf_call, bufnr, function()
    vim.cmd([[
      syntax clear
      syntax match ClangdTypeName "\(• \)\@<=.\+\(: \)\@="
    ]])
  end)
  api.nvim_set_hl(0, "ClangdTypeName", { link = "Underlined" })

  -- Mutable: jump_from updates win/buf after each gd so later jumps reuse
  -- the same editor window even when it no longer shows source_buf.
  local target = { win = source_win, buf = source_buf }

  vim.keymap.set("n", "gd", function()
    jump_from(bufnr, target, client_id)
  end, { buffer = bufnr, desc = "Go to type under cursor" })

  vim.keymap.set("n", "q", function()
    pcall(api.nvim_win_close, 0, true)
  end, { buffer = bufnr, desc = "Close type hierarchy" })

  api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    group = augroup,
    callback = function()
      M.type_to_location[bufnr] = nil
    end,
  })
end

local function handler(err, result, ctx, pos_params, source_win, source_buf)
  -- LSP null is vim.NIL, which is truthy. Do not index it.
  if err ~= nil and err ~= vim.NIL then
    local msg = type(err) == "table" and err.message or nil
    vim.notify(msg or "Type hierarchy failed", vim.log.levels.ERROR)
    return
  end

  if result == nil or result == vim.NIL then
    vim.notify("No type hierarchy for this symbol", vim.log.levels.INFO)
    return
  end

  local root = root_item(result)
  if not root then
    vim.notify("No type hierarchy for this symbol", vim.log.levels.INFO)
    return
  end

  local client_id = ctx.client_id
  local client = vim.lsp.get_clients({ id = client_id })[1]

  local function finish()
    render_tree(root, client_id, source_win, source_buf)
  end

  if not client or qualified_name(root) ~= (root.name or "?") then
    finish()
    return
  end

  -- If the follow-up is gated, the callback never runs — still show the tree.
  local sent = client:request("textDocument/symbolInfo", {
    textDocument = pos_params.textDocument,
    position = pos_params.position,
  }, function(si_err, si_result)
    if (si_err == nil or si_err == vim.NIL) and type(si_result) == "table" then
      apply_root_name(root, si_result[1])
    end
    finish()
  end, source_buf)
  if not sent then
    finish()
  end
end

function M.show()
  local bufnr = api.nvim_get_current_buf()
  local source_win = api.nvim_get_current_win()
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })[1]
  if not client then
    vim.notify("No clangd client", vim.log.levels.ERROR)
    return
  end

  local pos_params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local params = vim.tbl_deep_extend("force", {}, pos_params, {
    resolve = 3,
    direction = 2,
  })

  client:request("textDocument/typeHierarchy", params, function(err, result, ctx)
    handler(err, result, ctx, pos_params, source_win, bufnr)
  end, bufnr)
end

return M
