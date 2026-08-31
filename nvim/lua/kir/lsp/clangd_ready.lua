-- Single definition of "is clangd ready for this buffer?"
-- Used by type hierarchy, client.request gating, and the statusline.

local api = vim.api

local M = {}

local augroup = api.nvim_create_augroup("KirClangdReady", { clear = true })

-- Index: only "in progress" after we have seen a begin for this client.
-- Never-seen begin/end does not block (background index may be off).
local index_state = {} ---@type table<integer, { seen_begin: boolean, seen_end: boolean }>

-- Per client so LspRestart cannot reuse the old client's idle.
local file_state = {} ---@type table<integer, table<string, string>>
local refresh_queued = false
local last_notify = { msg = nil, at = 0 }

-- User-facing requests. Completion / tokens / inlay hints stay ungated.
local gated_methods = {
  ["textDocument/hover"] = true,
  ["textDocument/definition"] = true,
  ["textDocument/declaration"] = true,
  ["textDocument/typeDefinition"] = true,
  ["textDocument/implementation"] = true,
  ["textDocument/references"] = true,
  ["textDocument/rename"] = true,
  ["textDocument/prepareRename"] = true,
  ["textDocument/codeAction"] = true,
  ["textDocument/documentSymbol"] = true,
  ["workspace/symbol"] = true,
  ["textDocument/prepareCallHierarchy"] = true,
  ["callHierarchy/incomingCalls"] = true,
  ["callHierarchy/outgoingCalls"] = true,
  ["textDocument/prepareTypeHierarchy"] = true,
  ["typeHierarchy/supertypes"] = true,
  ["typeHierarchy/subtypes"] = true,
  ["textDocument/typeHierarchy"] = true,
  ["textDocument/switchSourceHeader"] = true,
  ["textDocument/symbolInfo"] = true,
  ["textDocument/ast"] = true,
  ["textDocument/formatting"] = true,
  ["textDocument/rangeFormatting"] = true,
  ["textDocument/signatureHelp"] = true,
}

local function clangd_filetypes()
  local fts = vim.lsp.config.clangd and vim.lsp.config.clangd.filetypes
  local set = {}
  if type(fts) == "table" then
    for _, ft in ipairs(fts) do
      set[ft] = true
    end
    return set
  end
  return {
    c = true,
    cpp = true,
    objc = true,
    objcpp = true,
    cuda = true,
    ["c.doxygen"] = true,
    ["cpp.doxygen"] = true,
  }
end

local function resolve_bufnr(bufnr)
  if type(bufnr) ~= "number" or bufnr == 0 then
    return api.nvim_get_current_buf()
  end
  return bufnr
end

local function uri_keys(uri)
  local keys = { uri }
  local ok, fname = pcall(vim.uri_to_fname, uri)
  if not ok or not fname or fname == "" then
    return keys
  end
  keys[#keys + 1] = vim.uri_from_fname(fname)
  local real = vim.uv.fs_realpath(fname)
  if real and real ~= fname then
    keys[#keys + 1] = vim.uri_from_fname(real)
  end
  return keys
end

local function client_files(client_id)
  local map = file_state[client_id]
  if not map then
    map = {}
    file_state[client_id] = map
  end
  return map
end

local function set_file_state(client_id, uri, state)
  local map = client_files(client_id)
  for _, key in ipairs(uri_keys(uri)) do
    map[key] = state
  end
end

local function get_file_state(client_id, uri)
  local map = file_state[client_id]
  if not map then
    return nil
  end
  for _, key in ipairs(uri_keys(uri)) do
    local state = map[key]
    if state ~= nil then
      return state
    end
  end
  return nil
end

local function clear_client_file_uri(client_id, uri)
  local map = file_state[client_id]
  if not map then
    return
  end
  for _, key in ipairs(uri_keys(uri)) do
    map[key] = nil
  end
  if not next(map) then
    file_state[client_id] = nil
  end
end

local function clear_file_uri(uri)
  for id, _ in pairs(file_state) do
    clear_client_file_uri(id, uri)
  end
end

local function refresh_ui()
  if refresh_queued then
    return
  end
  refresh_queued = true
  vim.defer_fn(function()
    refresh_queued = false
    api.nvim_exec_autocmds("User", { pattern = "KirClangdReady", modeline = false })
  end, 50)
end

local function notify_not_ready(reason)
  local now = vim.uv.hrtime()
  if last_notify.msg == reason and (now - last_notify.at) < 4e8 then
    return
  end
  last_notify.msg = reason
  last_notify.at = now
  vim.notify(reason, vim.log.levels.ERROR)
end

---@param client vim.lsp.Client
---@param bufnr integer
---@return string|nil reason
function M.not_ready(client, bufnr)
  if not client.initialized then
    return "clangd is not initialized yet"
  end

  bufnr = resolve_bufnr(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then
    return "clangd has not parsed this file yet"
  end

  -- Always wait for this file's clangd fileStatus. After LspRestart the
  -- map is empty, so we stay not-ready until the new client reports idle.
  local state = get_file_state(client.id, vim.uri_from_bufnr(bufnr))
  if state ~= "idle" then
    if state == nil then
      return "clangd has not parsed this file yet"
    end
    return "clangd is still parsing this file (" .. state .. ")"
  end

  local pending = client.progress.pending and client.progress.pending.backgroundIndexProgress
  if pending then
    return "clangd is still indexing"
  end

  local st = index_state[client.id]
  if st and st.seen_begin and not st.seen_end then
    return "clangd is still indexing"
  end

  return nil
end

--- nil = clangd is not for this file; otherwise "ready" or "not_ready".
---@param bufnr? integer
---@return "ready"|"not_ready"|nil
function M.status(bufnr)
  bufnr = resolve_bufnr(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local client = vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })[1]
  if not client then
    if clangd_filetypes()[vim.bo[bufnr].filetype] then
      return "not_ready"
    end
    return nil
  end

  if M.not_ready(client, bufnr) then
    return "not_ready"
  end
  return "ready"
end

function M.wrap_client(client)
  if client._kir_ready_wrapped then
    return
  end
  client._kir_ready_wrapped = true

  -- Neovim 0.12 installs a method_wrapper so both client:request() and
  -- client.request() work. Replace that wrapper and preserve the call style
  -- when forwarding, so we do not break either form.
  local orig_request = client.request
  client.request = function(...)
    local first = select(1, ...)
    local method, bufnr
    if first == client then
      method = select(2, ...)
      bufnr = select(5, ...)
    else
      method = first
      bufnr = select(4, ...)
    end

    if gated_methods[method] then
      local reason = M.not_ready(client, resolve_bufnr(bufnr))
      if reason then
        -- Do not invoke the handler: default hover/definition would notify again.
        notify_not_ready(reason)
        return false
      end
    end

    return orig_request(...)
  end
end

vim.lsp.handlers["textDocument/clangd.fileStatus"] = function(_, result, ctx)
  if type(result) ~= "table" or type(result.uri) ~= "string" then
    return
  end
  local state = type(result.state) == "string" and result.state or ""
  local client_id = ctx and ctx.client_id
  if client_id then
    set_file_state(client_id, result.uri, state)
  else
    for _, c in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
      set_file_state(c.id, result.uri, state)
    end
  end
  refresh_ui()
end

api.nvim_create_autocmd("LspProgress", {
  group = augroup,
  callback = function(ev)
    local data = ev.data
    if type(data) ~= "table" then
      return
    end
    local client = vim.lsp.get_client_by_id(data.client_id)
    if not client or client.name ~= "clangd" then
      return
    end
    local params = data.params
    if not params or tostring(params.token) ~= "backgroundIndexProgress" then
      return
    end
    local kind = type(params.value) == "table" and params.value.kind
    local st = index_state[client.id] or { seen_begin = false, seen_end = false }
    if kind == "begin" then
      st.seen_begin = true
      st.seen_end = false
    elseif kind == "end" then
      st.seen_end = true
    end
    index_state[client.id] = st
    refresh_ui()
  end,
})

api.nvim_create_autocmd("LspAttach", {
  group = augroup,
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client.name == "clangd" then
      M.wrap_client(client)
    end
    refresh_ui()
  end,
})

api.nvim_create_autocmd("LspDetach", {
  group = augroup,
  callback = function(ev)
    local id = ev.data.client_id
    local still_attached = 0
    local client = vim.lsp.get_client_by_id(id)
    if client then
      for buf in pairs(client.attached_buffers) do
        if buf ~= ev.buf then
          still_attached = still_attached + 1
        end
      end
    end
    if still_attached == 0 then
      index_state[id] = nil
      file_state[id] = nil
    end
    refresh_ui()
  end,
})

api.nvim_create_autocmd("BufDelete", {
  group = augroup,
  callback = function(ev)
    local ok, uri = pcall(vim.uri_from_bufnr, ev.buf)
    if ok and uri then
      clear_file_uri(uri)
    end
  end,
})

-- :e reload keeps the buffer and the old idle. Drop it so we wait for the
-- new parse. Do this on BufReadPost (before didOpen), not LspNotify didOpen:
-- that autocmd is scheduled and can wipe an idle that already arrived.
api.nvim_create_autocmd("BufReadPost", {
  group = augroup,
  callback = function(ev)
    -- Telescope / other previewers use unlisted buffers. Same URI as the
    -- real file — clearing that would make K/gd fail while you preview.
    if not vim.bo[ev.buf].buflisted then
      return
    end
    local clients = vim.lsp.get_clients({ bufnr = ev.buf, name = "clangd" })
    if #clients == 0 then
      return
    end
    local ok, uri = pcall(vim.uri_from_bufnr, ev.buf)
    if not ok or not uri then
      return
    end
    for _, c in ipairs(clients) do
      clear_client_file_uri(c.id, uri)
    end
    refresh_ui()
  end,
})

for _, client in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
  M.wrap_client(client)
end

return M
