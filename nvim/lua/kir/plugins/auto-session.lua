return {
  "rmagatti/auto-session",
  config = function()
    local auto_session = require("auto-session")

    ---@return table|nil
    local function qflist_stack_payload()
      local total = vim.fn.getqflist({ nr = "$" }).nr
      if total == 0 then
        return nil
      end

      local current = vim.fn.getqflist({ nr = 0 }).nr
      local lists = {}

      for i = 1, total do
        local qf = vim.fn.getqflist({ nr = i, all = true })
        local items = {}
        for _, item in ipairs(qf.items or {}) do
          local filename = item.filename
          if (not filename or filename == "") and item.bufnr and item.bufnr > 0 then
            if vim.api.nvim_buf_is_valid(item.bufnr) then
              filename = vim.api.nvim_buf_get_name(item.bufnr)
            end
          end
          items[#items + 1] = {
            filename = filename,
            lnum = item.lnum,
            col = item.col,
            end_lnum = item.end_lnum,
            end_col = item.end_col,
            text = item.text,
            type = item.type,
            valid = item.valid,
          }
        end
        lists[#lists + 1] = {
          title = qf.title,
          items = items,
        }
      end

      return { current = current, lists = lists }
    end

    ---@param decoded table
    local function restore_qflist_stack(decoded)
      if type(decoded.lists) ~= "table" then
        return
      end

      vim.fn.setqflist({}, "f")
      for _, qf in ipairs(decoded.lists) do
        vim.fn.setqflist({}, " ", {
          title = qf.title or "",
          items = qf.items or {},
        })
      end

      local current = decoded.current or #decoded.lists
      if current >= 1 and current <= #decoded.lists then
        vim.cmd(current .. "chistory")
      end
    end

    local function restore_nvim_tree()
      local ok, api = pcall(require, "nvim-tree.api")
      if not ok then
        return
      end
      if vim.g._session_nvim_tree_open then
        api.tree.open()
      else
        api.tree.close()
      end
    end

    auto_session.setup({
      auto_restore_enabled = false,
      auto_session_suppress_dirs = { "~/", "~/Dev/", "~/Downloads", "~/Documents", "~/Desktop/" },
      -- Don't use built-in close_unsupported_windows: it runs before pre_save on
      -- exit and would always record the tree as closed. We only store a flag;
      -- post_restore applies open/closed. Keep the tree open during save.
      close_unsupported_windows = false,
      pre_save_cmds = {
        function()
          local ok, api = pcall(require, "nvim-tree.api")
          if ok then
            vim.g._session_nvim_tree_open = api.tree.is_visible()
          else
            vim.g._session_nvim_tree_open = false
          end
        end,
      },
      save_extra_data = function(_)
        local payload = {
          nvim_tree_open = vim.g._session_nvim_tree_open and true or false,
        }
        local qf = qflist_stack_payload()
        if qf then
          payload.current = qf.current
          payload.lists = qf.lists
        end
        return vim.json.encode(payload)
      end,
      restore_extra_data = function(_, data)
        local ok, decoded = pcall(vim.json.decode, data)
        if not ok or type(decoded) ~= "table" then
          return
        end
        vim.g._session_nvim_tree_open = decoded.nvim_tree_open and true or false
        restore_qflist_stack(decoded)
      end,
      post_restore_cmds = {
        function()
          -- Schedule so we win against nvim-tree directory hijack during restore.
          vim.schedule(restore_nvim_tree)
        end,
      },
    })

    local keymap = vim.keymap

    keymap.set("n", "<leader>wr", "<cmd>AutoSession restore<CR>", { desc = "Restore session for cwd" }) -- restore last workspace session for current directory
    keymap.set("n", "<leader>ws", "<cmd>AutoSession save<CR>", { desc = "Save session for auto session root dir" }) -- save workspace session for current working directory
  end,
}
