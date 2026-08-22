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
  if type(detail) == "string" and detail ~= "" and detail ~= name then
    if detail:sub(-#name) == name then
      return detail
    end
    return detail .. "::" .. name
  end
  return name
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
  if type(node.data) == "string" and node.data ~= "" then
    return node.data
  end
  local start = node.range and node.range.start
  return table.concat({
    node.uri or "",
    node.name or "",
    start and start.line or 0,
    start and start.character or 0,
  }, "\0")
end

local function format_tree(node, visited, result, padding, type_to_location)
  visited[visit_key(node)] = true

  local location = { uri = node.uri, range = node.range }
  table.insert(result, padding .. (" • %s: %s"):format(qualified_name(node), kind_name(node.kind)))
  type_to_location[#result] = location
  local path = file_path(node)
  if path then
    table.insert(result, padding .. "   " .. path)
    type_to_location[#result] = location
  end

  if node.parents and #node.parents > 0 then
    table.insert(result, padding .. "   Parents:")
    for _, parent in ipairs(sorted_nodes(node.parents)) do
      if not visited[visit_key(parent)] then
        format_tree(parent, visited, result, padding .. "   ", type_to_location)
      end
    end
  end

  if node.children and #node.children > 0 then
    table.insert(result, padding .. "   Children:")
    for _, child in ipairs(sorted_nodes(node.children)) do
      if not visited[visit_key(child)] then
        format_tree(child, visited, result, padding .. "   ", type_to_location)
      end
    end
  end

  return result
end

local function jump_from(bufnr, source_win, client_id)
  local line = api.nvim_win_get_cursor(0)[1]
  local location = M.type_to_location[bufnr] and M.type_to_location[bufnr][line]
  if not location then
    return
  end
  if api.nvim_win_is_valid(source_win) then
    api.nvim_set_current_win(source_win)
  end
  vim.lsp.util.show_document(location, M.offset_encoding[client_id], { focus = true })
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

local function render_tree(root, client_id, source_win)
  local client = vim.lsp.get_clients({ id = client_id })[1]
  if not client then
    return
  end

  M.offset_encoding[client_id] = client.offset_encoding
  vim.cmd.split(("%s: type hierarchy"):format(qualified_name(root)))
  local bufnr = api.nvim_get_current_buf()
  M.type_to_location[bufnr] = {}

  local lines = format_tree(root, {}, {}, "", M.type_to_location[bufnr])
  api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

  vim.bo.modifiable = false
  vim.bo.filetype = "ClangdTypeHierarchy"
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "wipe"
  vim.bo.buflisted = true
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.spell = false
  vim.wo.cursorline = true
  api.nvim_win_set_height(0, math.min(#lines, 15))

  vim.cmd([[
    syntax clear
    syntax match ClangdTypeName "\(• \)\@<=.\+\(: \)\@="
  ]])
  api.nvim_set_hl(0, "ClangdTypeName", { link = "Underlined" })

  vim.keymap.set("n", "gd", function()
    jump_from(bufnr, source_win, client_id)
  end, { buffer = bufnr, desc = "Go to type under cursor" })

  api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    group = augroup,
    callback = function()
      M.type_to_location[bufnr] = nil
    end,
  })
end

local function handler(err, result, ctx, pos_params)
  if err then
    vim.notify(err.message or "Type hierarchy failed", vim.log.levels.ERROR)
    return
  end

  local root = result and root_item(result)
  if not root then
    vim.notify("No type hierarchy for this symbol", vim.log.levels.INFO)
    return
  end

  local client_id = ctx.client_id
  local source_win = api.nvim_get_current_win()
  local client = vim.lsp.get_clients({ id = client_id })[1]
  if not client then
    return
  end

  local function finish()
    render_tree(root, client_id, source_win)
  end

  if qualified_name(root) ~= (root.name or "?") then
    finish()
    return
  end

  client:request("textDocument/symbolInfo", {
    textDocument = pos_params.textDocument,
    position = pos_params.position,
  }, function(si_err, si_result)
    if not si_err and type(si_result) == "table" then
      apply_root_name(root, si_result[1])
    end
    finish()
  end, ctx.bufnr)
end

function M.show()
  local bufnr = api.nvim_get_current_buf()
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })[1]
  if not client then
    vim.notify("No clangd client", vim.log.levels.WARN)
    return
  end

  local pos_params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local params = vim.tbl_deep_extend("force", {}, pos_params, {
    resolve = 3,
    direction = 2,
  })

  client:request("textDocument/typeHierarchy", params, function(err, result, ctx)
    handler(err, result, ctx, pos_params)
  end, bufnr)
end

return M
