return {
  "rmagatti/auto-session",
  config = function()
    local auto_session = require("auto-session")

    ---@return string|nil
    local function serialize_qflist_stack()
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

      return vim.json.encode({ current = current, lists = lists })
    end

    ---@param data string
    local function restore_qflist_stack(data)
      local ok, decoded = pcall(vim.json.decode, data)
      if not ok or type(decoded) ~= "table" or type(decoded.lists) ~= "table" then
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

    auto_session.setup({
      auto_restore_enabled = false,
      auto_session_suppress_dirs = { "~/", "~/Dev/", "~/Downloads", "~/Documents", "~/Desktop/" },
      -- Persist the full quickfix stack (titles + items + current index).
      save_extra_data = function(_)
        return serialize_qflist_stack()
      end,
      restore_extra_data = function(_, data)
        restore_qflist_stack(data)
      end,
    })

    local keymap = vim.keymap

    keymap.set("n", "<leader>wr", "<cmd>AutoSession restore<CR>", { desc = "Restore session for cwd" }) -- restore last workspace session for current directory
    keymap.set("n", "<leader>ws", "<cmd>AutoSession save<CR>", { desc = "Save session for auto session root dir" }) -- save workspace session for current working directory
  end,
}
