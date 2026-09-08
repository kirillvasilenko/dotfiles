-- Unresolved GitHub PR review threads, in the buffers you are already reading.
--
-- GitHub unanchors a review thread from the diff as soon as a commit touches the
-- commented line: the thread is flagged Outdated, disappears from Files changed,
-- and the comments panel will not reliably reopen it. So threads are enumerated
-- from the API instead of read off the diff, which is the only way outdated ones
-- stay reachable. See bin/gh-pr-comments for the shell equivalent.
--
-- Requires: gh, authenticated (`gh auth login`). nvim >= 0.10 (vim.system).
--
--   :PRThreads [pr]   load unresolved threads for a PR -> quickfix + markers
--   :PRThreadsAll     same, but everyone's threads, not only yours
--   :PRThread         show the full discussion under the cursor
--   :PRThreadsClear   drop the markers
--
--   :PRComment        start a new thread on this line (or visual range)
--   :PRReply          reply to the thread under the cursor
--   :PRResolve        resolve / unresolve the thread under the cursor
--
-- Comments are published the moment you send them. GitHub's web UI parks inline
-- comments in a *pending review* that stays invisible to the author until you
-- remember to submit it; POST .../pulls/{n}/comments does not, so that failure
-- mode cannot happen here.

local keymap = vim.keymap

local ns = vim.api.nvim_create_namespace("kir_prcomments")

local state = {
  root = nil, -- git toplevel
  by_path = {}, -- relpath -> { thread, ... }
  count = 0,
  pr = nil, -- last resolved PR: number, owner, repo, headRefOid
  float_thread = nil, -- thread rendered in the open float, for r / R
  diff_cache = {}, -- "pr:path" -> commentable line set
}

--- Ask git, don't probe the filesystem: in a linked worktree `.git` is a file
--- rather than a directory, and reviews happen in worktrees here.
---@param path string
---@return string|nil
local function repo_root(path)
  local res = vim.system({ "git", "rev-parse", "--show-toplevel" }, { cwd = path, text = true }):wait()
  if res.code == 0 then
    local root = vim.trim(res.stdout or "")
    if root ~= "" then
      return root
    end
  end
  return vim.fs.root(path, ".git")
end

--- Run a command to completion, returning stdout.
---@param cmd string[]
---@param cwd string
---@return string|nil stdout, string|nil err
local function run(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if res.code ~= 0 then
    return nil, (res.stderr or ""):gsub("%s+$", "")
  end
  return res.stdout
end

local QUERY = [[
query($owner:String!, $repo:String!, $pr:Int!, $endCursor:String) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100, after:$endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id isResolved isOutdated path line originalLine
          comments(first:100) {
            totalCount
            nodes { url body createdAt author { login } }
          }
        }
      }
    }
  }
}]]

--- gh's built-in --jq takes no external variables, so the login is inlined.
--- `tojson` keeps each thread on one line: comment bodies contain newlines.
---@param login string|nil nil means "everyone"
---@return string
local function jq_filter(login)
  local mine = ""
  if login then
    mine = string.format('| select(any(.comments.nodes[]; .author.login == "%s"))', login)
  end
  return ".data.repository.pullRequest.reviewThreads.nodes[]\n"
    .. "| select(.isResolved | not)\n"
    .. mine
    .. "\n| tojson"
end

---@param url string
---@return string|nil "owner/repo"
local function nwo_from_url(url)
  local owner, repo = url:match("github%.com[:/]([^/]+)/(.-)%.git%s*$")
  if not owner then
    owner, repo = url:match("github%.com[:/]([^/]+)/([^/%s]+)%s*$")
  end
  return owner and (owner .. "/" .. repo) or nil
end

--- Which GitHub repo do this checkout's PRs live in?
---
--- A checkout with several contributor remotes and no `origin` (reviewing from
--- other people's forks) leaves gh unable to guess, so the upstream is resolved
--- explicitly: g:prcomments_repo, then gh's own default, then the first remote
--- named upstream/official/origin.
---@param root string
---@return string|nil nwo, string|nil err
local function resolve_repo(root)
  if vim.g.prcomments_repo and vim.g.prcomments_repo ~= "" then
    return vim.g.prcomments_repo
  end

  local out = run({ "gh", "repo", "set-default", "--view" }, root)
  if out and vim.trim(out) ~= "" and vim.trim(out):match("^[^/]+/[^/]+$") then
    return vim.trim(out)
  end

  local remotes = run({ "git", "remote", "-v" }, root) or ""
  local by_name = {}
  for name, url in remotes:gmatch("(%S+)%s+(%S+)%s+%(fetch%)") do
    by_name[name] = url
  end
  for _, name in ipairs({ "upstream", "official", "origin" }) do
    if by_name[name] then
      local nwo = nwo_from_url(by_name[name])
      if nwo then
        return nwo
      end
    end
  end

  return nil,
    "cannot tell which repo this PR belongs to — run `gh repo set-default` once, "
      .. "or set vim.g.prcomments_repo = 'owner/repo'"
end

--- Resolve owner/repo/number for PR `pr`, or the PR of the current branch.
---@param root string
---@param pr string|nil
---@return table|nil info, string|nil err
local function pr_info(root, pr)
  local nwo, rerr = resolve_repo(root)
  if not nwo then
    return nil, rerr
  end

  local fields = "number,headRefOid,url,title"
  local out, err
  if pr and pr ~= "" then
    out, err = run({ "gh", "pr", "view", pr, "-R", nwo, "--json", fields }, root)
    if not out then
      return nil, string.format("PR %s not found in %s (%s)", pr, nwo, err or "gh failed")
    end
  else
    -- The branch may have no upstream (fetched straight from a contributor's
    -- fork), so match the PR by head branch name rather than by tracking ref.
    local branch = run({ "git", "rev-parse", "--abbrev-ref", "HEAD" }, root)
    branch = branch and vim.trim(branch) or ""
    out, err = run({
      "gh", "pr", "list", "-R", nwo, "--head", branch, "--state", "all",
      "--limit", "1", "--json", fields,
    }, root)
    if not out then
      return nil, string.format("could not list PRs in %s (%s)", nwo, err or "gh failed")
    end
    local ok, list = pcall(vim.json.decode, out, { luanil = { object = true } })
    if not ok or type(list) ~= "table" or #list == 0 then
      return nil, string.format("no PR in %s for branch '%s' — pass a PR number", nwo, branch)
    end
    out = vim.json.encode(list[1])
  end

  local ok, info = pcall(vim.json.decode, out, { luanil = { object = true } })
  if not ok then
    return nil, "could not parse gh output"
  end
  info.owner, info.repo = nwo:match("^([^/]+)/(.+)$")
  return info
end

--- Outdated threads have no current line, so fall back to where the comment was
--- originally left. That code has since changed, hence the `!` marker.
---@param t table
---@return integer
local function thread_line(t)
  local l = t.line or t.originalLine or 1
  return math.max(1, l)
end

---@param t table
---@return string
local function first_line_of(t)
  local c = t.comments.nodes[1]
  for _, line in ipairs(vim.split(c.body or "", "\n")) do
    local s = vim.trim(line)
    if s ~= "" then
      return s
    end
  end
  return "(empty)"
end

--- diffview names its buffers diffview://<gitdir>/<rev>/<path>, one per side.
--- Deleted lines exist only in the base-revision buffer, so that is where a
--- LEFT-side comment has to be written from.
---@param bufnr integer
---@return string|nil relpath, string|nil rev
local function diffview_target(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local rev, path = name:match("^diffview://.*/%.git/([^/]+)/(.+)$")
  if rev and path then
    return path, rev
  end
  return nil
end

--- Which side of the diff does this buffer show? The head revision (and any
--- ordinary working-tree buffer) is RIGHT; anything else diffview opened is the
--- base, so LEFT.
---@param bufnr integer
---@return string
local function buf_side(bufnr)
  local _, rev = diffview_target(bufnr)
  if not rev then
    return "RIGHT"
  end
  local head = run({ "git", "rev-parse", "HEAD" }, state.root)
  head = head and vim.trim(head) or ""
  return (rev ~= "" and head:sub(1, #rev) == rev) and "RIGHT" or "LEFT"
end

---@param bufnr integer
---@return string|nil
local function buf_relpath(bufnr)
  if not state.root then
    return nil
  end
  local dv = diffview_target(bufnr)
  if dv then
    return dv
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return nil
  end
  local abs = vim.fn.fnamemodify(name, ":p")
  local prefix = state.root .. "/"
  if abs:sub(1, #prefix) ~= prefix then
    return nil
  end
  return abs:sub(#prefix + 1)
end

--- End-of-line marker on every line that carries a thread, so the discussion is
--- discoverable while scrolling instead of only through the quickfix list.
---@param bufnr integer
local function decorate(bufnr)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local rel = buf_relpath(bufnr)
  local threads = rel and state.by_path[rel]
  if not threads then
    return
  end

  local last = vim.api.nvim_buf_line_count(bufnr)
  for _, t in ipairs(threads) do
    local lnum = math.min(thread_line(t), last)
    local mark = t.isOutdated and "!" or "*"
    local text = string.format(" %s %d msg  %s", mark, t.comments.totalCount, first_line_of(t))
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, lnum - 1, 0, {
      -- strcharpart, not sub: byte-slicing splits multibyte characters.
      virt_text = { { vim.fn.strcharpart(text, 0, 120), t.isOutdated and "DiagnosticVirtualTextWarn" or "DiagnosticVirtualTextHint" } },
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
  end
end

local function decorate_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    decorate(bufnr)
  end
end

---@param info table
local function to_quickfix(info)
  local items = {}
  for _, threads in pairs(state.by_path) do
    for _, t in ipairs(threads) do
      items[#items + 1] = {
        filename = state.root .. "/" .. t.path,
        lnum = thread_line(t),
        col = 1,
        text = string.format(
          "%s %d msg  %s",
          t.isOutdated and "[outdated]" or "[current] ",
          t.comments.totalCount,
          first_line_of(t)
        ),
      }
    end
  end
  table.sort(items, function(a, b)
    if a.filename ~= b.filename then
      return a.filename < b.filename
    end
    return a.lnum < b.lnum
  end)
  vim.fn.setqflist({}, " ", {
    title = string.format("PR #%d unresolved threads", info.number),
    items = items,
  })
end

---@param pr string|nil
---@param only_mine boolean
local function load(pr, only_mine)
  local root = repo_root(vim.fn.expand("%:p:h") ~= "" and vim.fn.expand("%:p:h") or vim.fn.getcwd())
  if not root then
    vim.notify("prcomments: not inside a git repo", vim.log.levels.ERROR)
    return
  end

  local info, err = pr_info(root, pr)
  if not info then
    vim.notify("prcomments: " .. err, vim.log.levels.ERROR)
    return
  end

  local login = nil
  if only_mine then
    local out, lerr = run({ "gh", "api", "user", "-q", ".login" }, root)
    if not out then
      vim.notify("prcomments: " .. (lerr or "could not resolve your login"), vim.log.levels.ERROR)
      return
    end
    login = vim.trim(out)
  end

  local head, _ = run({ "git", "rev-parse", "HEAD" }, root)
  if head and info.headRefOid and vim.trim(head) ~= info.headRefOid then
    vim.notify(
      "prcomments: local HEAD is not the PR head commit — line numbers may be off",
      vim.log.levels.WARN
    )
  end

  local out, gerr = run({
    "gh", "api", "graphql", "--paginate",
    "-f", "owner=" .. info.owner,
    "-f", "repo=" .. info.repo,
    "-F", "pr=" .. info.number,
    "-f", "query=" .. QUERY,
    "--jq", jq_filter(login),
  }, root)
  if not out then
    vim.notify("prcomments: " .. (gerr or "gh api failed"), vim.log.levels.ERROR)
    return
  end

  state.root = root
  state.pr = info
  state.by_path = {}
  state.count = 0
  for _, line in ipairs(vim.split(out, "\n")) do
    if vim.trim(line) ~= "" then
      local ok, t = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
      if ok and t and t.path then
        state.by_path[t.path] = state.by_path[t.path] or {}
        table.insert(state.by_path[t.path], t)
        state.count = state.count + 1
      end
    end
  end

  if state.count == 0 then
    vim.notify(string.format("prcomments: no unresolved threads in #%d", info.number))
    return
  end

  to_quickfix(info)
  decorate_all()
  vim.cmd("copen")
  vim.notify(string.format("prcomments: %d unresolved thread(s) in #%d", state.count, info.number))
end

--- Threads on the cursor line, else the nearest one in this file.
---@return table[]|nil
local function threads_at_cursor()
  local rel = buf_relpath(vim.api.nvim_get_current_buf())
  local threads = rel and state.by_path[rel]
  if not threads or #threads == 0 then
    return nil
  end

  local cur = vim.fn.line(".")
  local exact = vim.tbl_filter(function(t)
    return thread_line(t) == cur
  end, threads)
  if #exact > 0 then
    return exact
  end

  local best, dist = nil, math.huge
  for _, t in ipairs(threads) do
    local d = math.abs(thread_line(t) - cur)
    if d < dist then
      best, dist = t, d
    end
  end
  return best and { best } or nil
end


---------------------------------------------------------------------------
-- writing: new thread, reply, resolve
---------------------------------------------------------------------------

--- Call gh and decode its JSON. The request body goes on stdin so bodies with
--- quotes, newlines or backticks never have to survive shell quoting.
---@param args string[] arguments after `gh`
---@param body table|nil JSON payload for `--input -`
---@return table|nil decoded, string|nil err
local function gh_json(args, body)
  local cmd = { "gh" }
  vim.list_extend(cmd, args)
  local opts = { cwd = state.root, text = true }
  if body then
    opts.stdin = vim.json.encode(body)
  end
  local res = vim.system(cmd, opts):wait()
  if res.code ~= 0 then
    -- gh reports GraphQL errors on stdout with a non-zero exit.
    local msg = vim.trim((res.stderr or "") .. " " .. (res.stdout or ""))
    return nil, msg ~= "" and msg or ("gh exited " .. res.code)
  end
  local ok, decoded = pcall(vim.json.decode, res.stdout, { luanil = { object = true } })
  return ok and decoded or {}, nil
end

--- Resolve (and cache) the PR for this checkout, so commenting works without
--- having run :PRThreads first.
---@return table|nil info, string|nil err
local function ensure_pr()
  local dir = vim.fn.expand("%:p:h")
  if dir == "" then
    dir = vim.fn.getcwd()
  end
  local root = state.root or repo_root(dir)
  if not root then
    return nil, "not inside a git repo"
  end
  state.root = root
  if state.pr then
    return state.pr
  end
  local info, err = pr_info(root, nil)
  if not info then
    return nil, err
  end
  state.pr = info
  return info
end

--- A line number is only meaningful against the commit GitHub anchors to.
---@param info table
---@return boolean
local function head_matches(info)
  local head = run({ "git", "rev-parse", "HEAD" }, state.root)
  return (head ~= nil) and (info.headRefOid ~= nil) and (vim.trim(head) == info.headRefOid)
end

--- Scratch split to write a comment in. <C-s> sends, :q discards.
---@param title string
---@param on_send fun(body: string): boolean, string|nil
local function compose(title, on_send)
  vim.cmd("botright 12split")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"
  vim.wo[0].winbar = title .. "   —   <C-s> send, :q discard"

  local function send()
    local body = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
    if body == "" then
      vim.notify("prcomments: empty comment, nothing sent", vim.log.levels.WARN)
      return
    end
    local ok, err = on_send(body)
    if not ok then
      vim.notify("prcomments: " .. (err or "send failed"), vim.log.levels.ERROR)
      return
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  keymap.set({ "n", "i" }, "<C-s>", send, { buffer = buf, desc = "Send comment" })
  vim.cmd("startinsert")
end


--- GitHub only accepts an inline comment on a line that appears in the PR's
--- patch for that file — added lines and context lines. Anywhere else comes back
--- as an opaque 422 ("line could not be resolved"), so the set is computed up
--- front and checked before the comment is written rather than after.
---@param info table
---@param path string
---@return table|nil sides { right = {[line]=true}, left = {[line]=true} }
---@return string|nil err
local function commentable_lines(info, path)
  state.diff_cache = state.diff_cache or {}
  local key = string.format("%d:%s", info.number, path)
  if state.diff_cache[key] then
    return state.diff_cache[key]
  end

  local out, err = run({
    "gh", "api", "--paginate",
    string.format("repos/%s/%s/pulls/%d/files", info.owner, info.repo, info.number),
    "--jq", string.format(".[] | select(.filename == %s) | .patch // \"\"", vim.json.encode(path)),
  }, state.root)
  if not out then
    return nil, err
  end
  if vim.trim(out) == "" then
    -- File not in the diff at all, or a patch GitHub declined to render.
    return nil, nil
  end

  -- Added and context lines are addressable on the right; deleted and context
  -- lines on the left. A pure deletion has no right-hand line at all, which is
  -- why LEFT support is needed for delete-only PRs.
  local sides = { right = {}, left = {} }
  local old_cur, new_cur
  for _, l in ipairs(vim.split(out, "\n")) do
    local a, c = l:match("^@@%s+%-(%d+)[%d,]*%s+%+(%d+)")
    if a then
      old_cur, new_cur = tonumber(a), tonumber(c)
    elseif new_cur then
      local ch = l:sub(1, 1)
      if ch == "+" then
        sides.right[new_cur] = true
        new_cur = new_cur + 1
      elseif ch == "-" then
        sides.left[old_cur] = true
        old_cur = old_cur + 1
      elseif ch == " " then
        sides.right[new_cur] = true
        sides.left[old_cur] = true
        new_cur, old_cur = new_cur + 1, old_cur + 1
      end
      -- "\" is the no-newline-at-EOF marker; it advances nothing.
    end
  end

  state.diff_cache[key] = sides
  return sides
end

---@param lines table<integer, boolean>
---@param want integer
---@return integer|nil
local function nearest_commentable(lines, want)
  local best, dist = nil, math.huge
  for l in pairs(lines) do
    local d = math.abs(l - want)
    if d < dist then
      best, dist = l, d
    end
  end
  return best
end

--- Start a new thread on `line1`..`line2` of the current buffer.
---@param line1 integer
---@param line2 integer
local function new_comment(line1, line2)
  local info, err = ensure_pr()
  if not info then
    vim.notify("prcomments: " .. err, vim.log.levels.ERROR)
    return
  end
  local rel = buf_relpath(vim.api.nvim_get_current_buf())
  if not rel then
    vim.notify("prcomments: this buffer is not a file inside the repo", vim.log.levels.ERROR)
    return
  end
  if not head_matches(info) then
    vim.notify(
      "prcomments: HEAD is not the PR head commit — refusing to comment, GitHub would "
        .. "anchor it to a different line. Check out the PR head first.",
      vim.log.levels.ERROR
    )
    return
  end

  local side = buf_side(vim.api.nvim_get_current_buf())
  local sides, lerr = commentable_lines(info, rel)
  local ok_lines = sides and (side == "LEFT" and sides.left or sides.right)
  if lerr then
    vim.notify("prcomments: could not read the PR diff (" .. lerr .. ")", vim.log.levels.ERROR)
    return
  end
  if ok_lines then
    local bad = nil
    for l = line1, line2 do
      if not ok_lines[l] then
        bad = l
        break
      end
    end
    if bad then
      local near = nearest_commentable(ok_lines, bad)
      vim.notify(
        string.format(
          "prcomments: line %d of %s is not part of this PR's diff on the %s side, so "
            .. "GitHub will not anchor a comment there.%s",
          bad,
          rel,
          side,
          near and (" Nearest commentable line is " .. near .. ".") or ""
        ),
        vim.log.levels.ERROR
      )
      return
    end
  end

  local where = (line1 == line2) and tostring(line1) or (line1 .. "-" .. line2)
  local title = string.format("PR #%d  new comment on %s:%s (%s)", info.number, rel, where, side)
  compose(title, function(body)
    local payload = {
      body = body,
      commit_id = info.headRefOid,
      path = rel,
      line = line2,
      side = side,
    }
    if line1 < line2 then
      payload.start_line = line1
      payload.start_side = side
    end
    local res, perr = gh_json({
      "api", "--method", "POST",
      string.format("repos/%s/%s/pulls/%d/comments", info.owner, info.repo, info.number),
      "--input", "-",
    }, payload)
    if not res then
      if perr and perr:find("pull_request_review_thread.line") then
        perr = "GitHub rejected the line: it is not part of this PR's diff"
      end
      return false, perr
    end
    vim.notify("prcomments: published — " .. (res.html_url or "ok"))
    return true
  end)
end

local REPLY_MUTATION = [[
mutation($threadId:ID!, $body:String!) {
  addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, body:$body}) {
    comment { url createdAt body author { login } }
  }
}]]

local RESOLVE_MUTATION = [[
mutation($threadId:ID!) {
  resolveReviewThread(input:{threadId:$threadId}) { thread { isResolved } }
}]]

local UNRESOLVE_MUTATION = [[
mutation($threadId:ID!) {
  unresolveReviewThread(input:{threadId:$threadId}) { thread { isResolved } }
}]]

---@param thread table|nil defaults to the thread under the cursor
local function reply(thread)
  thread = thread or (threads_at_cursor() or {})[1]
  if not thread then
    vim.notify("prcomments: no thread here (run :PRThreads first?)", vim.log.levels.WARN)
    return
  end
  compose(string.format("Reply to %s:%d", thread.path, thread_line(thread)), function(body)
    local res, err = gh_json({
      "api", "graphql",
      "-f", "query=" .. REPLY_MUTATION,
      "-f", "threadId=" .. thread.id,
      "-f", "body=" .. body,
    })
    if not res then
      return false, err
    end
    -- Keep the in-memory thread current so the float shows the reply without a refetch.
    local posted = res.data
      and res.data.addPullRequestReviewThreadReply
      and res.data.addPullRequestReviewThreadReply.comment
    if posted then
      table.insert(thread.comments.nodes, posted)
      thread.comments.totalCount = thread.comments.totalCount + 1
      decorate_all()
    end
    vim.notify("prcomments: replied — " .. ((posted and posted.url) or "ok"))
    return true
  end)
end

--- Resolve, or unresolve if already resolved.
---@param thread table|nil defaults to the thread under the cursor
local function resolve_toggle(thread)
  thread = thread or (threads_at_cursor() or {})[1]
  if not thread then
    vim.notify("prcomments: no thread here (run :PRThreads first?)", vim.log.levels.WARN)
    return
  end
  local res, err = gh_json({
    "api", "graphql",
    "-f", "query=" .. (thread.isResolved and UNRESOLVE_MUTATION or RESOLVE_MUTATION),
    "-f", "threadId=" .. thread.id,
  })
  if not res then
    vim.notify("prcomments: " .. (err or "mutation failed"), vim.log.levels.ERROR)
    return
  end

  thread.isResolved = not thread.isResolved
  if thread.isResolved then
    -- The working set is unresolved threads, so a resolved one drops out of it.
    local list = state.by_path[thread.path] or {}
    for i, t in ipairs(list) do
      if t.id == thread.id then
        table.remove(list, i)
        state.count = state.count - 1
        break
      end
    end
  end
  decorate_all()
  vim.notify(string.format("prcomments: thread %s", thread.isResolved and "resolved" or "reopened"))
end

--- GitHub timestamps are ISO-8601 UTC; show them in the machine's local zone so
--- "when was this said" reads correctly from wherever the editor is running.
---@param iso string|nil
---@return string
local function fmt_time(iso)
  if not iso or iso == "" then
    return ""
  end
  local y, mo, d, h, mi, sec = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then
    return iso
  end
  -- os.time reads the table as local time, so add the local offset from UTC.
  local as_local = os.time({
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec), isdst = false,
  })
  local now = os.time()
  local offset = os.difftime(now, os.time(os.date("!*t", now)))
  return os.date("%Y-%m-%d %H:%M", as_local + offset)
end

---@param threads table[]
---@return string[]
local function render(threads)
  local lines = {}
  for i, t in ipairs(threads) do
    if i > 1 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = string.rep("═", 76)
      lines[#lines + 1] = ""
    end
    lines[#lines + 1] = string.format(
      "%s:%d   %s   %d message(s)",
      t.path,
      thread_line(t),
      t.isOutdated and "OUTDATED — line has changed since" or "current",
      t.comments.totalCount
    )
    lines[#lines + 1] = string.rep("─", 76)
    for j, c in ipairs(t.comments.nodes) do
      if j > 1 then
        lines[#lines + 1] = ""
      end
      local author = c.author and c.author.login or "(unknown)"
      lines[#lines + 1] = string.format("%s  ·  %s", author, fmt_time(c.createdAt))
      for _, l in ipairs(vim.split((c.body or ""):gsub("\r", ""), "\n")) do
        lines[#lines + 1] = "  " .. l
      end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = t.comments.nodes[1] and t.comments.nodes[1].url or ""
  end
  return lines
end

local function show()
  local threads = threads_at_cursor()
  if not threads then
    vim.notify("prcomments: no thread here (run :PRThreads first?)", vim.log.levels.WARN)
    return
  end

  local lines = render(threads)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"

  local width = math.min(90, math.floor(vim.o.columns * 0.85))
  local height = math.min(#lines + 1, math.floor(vim.o.lines * 0.8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " PR thread ",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  local thread = threads[1]
  state.float_thread = thread
  local url = thread.comments.nodes[1] and thread.comments.nodes[1].url

  keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, desc = "Close thread" })
  keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf, desc = "Close thread" })
  keymap.set("n", "r", function()
    vim.api.nvim_win_close(win, true)
    reply(thread)
  end, { buffer = buf, desc = "Reply to thread" })
  keymap.set("n", "R", function()
    vim.api.nvim_win_close(win, true)
    resolve_toggle(thread)
  end, { buffer = buf, desc = "Resolve / unresolve thread" })
  -- vim.ui.open needs a desktop; on a headless remote yanking the link is the
  -- way to get it onto the local machine.
  keymap.set("n", "gy", function()
    if url then
      vim.fn.setreg('"', url)
      vim.fn.setreg("+", url)
      vim.notify(url)
    end
  end, { buffer = buf, desc = "Yank thread permalink" })
  keymap.set("n", "gx", function()
    if url then
      vim.ui.open(url)
    end
  end, { buffer = buf, desc = "Open thread in browser" })
end

local function clear()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end
  end
  state.by_path = {}
  state.count = 0
end

-- Re-mark buffers opened after the fetch (e.g. jumping through the quickfix list).
vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
  callback = function(ev)
    if state.count > 0 then
      decorate(ev.buf)
    end
  end,
})

vim.api.nvim_create_user_command("PRThreads", function(o)
  load(o.args, true)
end, { nargs = "?", desc = "Unresolved PR threads (yours)" })

vim.api.nvim_create_user_command("PRThreadsAll", function(o)
  load(o.args, false)
end, { nargs = "?", desc = "Unresolved PR threads (everyone's)" })

vim.api.nvim_create_user_command("PRComment", function(o)
  new_comment(o.line1, o.line2)
end, { range = true, desc = "New PR comment on this line / range" })

vim.api.nvim_create_user_command("PRReply", function()
  reply(nil)
end, { desc = "Reply to PR thread under cursor" })

vim.api.nvim_create_user_command("PRResolve", function()
  resolve_toggle(nil)
end, { desc = "Resolve / unresolve PR thread under cursor" })

vim.api.nvim_create_user_command("PRThread", show, { desc = "Show PR thread under cursor" })
vim.api.nvim_create_user_command("PRThreadsClear", clear, { desc = "Clear PR thread markers" })

keymap.set("n", "<leader>gp", "<cmd>PRThreads<CR>", { desc = "PR unresolved threads (mine)" })
keymap.set("n", "<leader>gP", "<cmd>PRThreadsAll<CR>", { desc = "PR unresolved threads (all)" })
keymap.set("n", "<leader>gv", "<cmd>PRThread<CR>", { desc = "PR thread under cursor" })
keymap.set("n", "<leader>gn", "<cmd>PRComment<CR>", { desc = "PR comment on this line" })
keymap.set("x", "<leader>gn", ":PRComment<CR>", { desc = "PR comment on selection" })
keymap.set("n", "<leader>gr", "<cmd>PRReply<CR>", { desc = "PR reply to thread" })
keymap.set("n", "<leader>gR", "<cmd>PRResolve<CR>", { desc = "PR resolve / unresolve thread" })
