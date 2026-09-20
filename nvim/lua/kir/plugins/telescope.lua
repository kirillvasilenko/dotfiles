return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    "nvim-tree/nvim-web-devicons",
    "nvim-telescope/telescope-live-grep-args.nvim",
    "folke/todo-comments.nvim",
  },
  config = function()
    local telescope = require("telescope")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local finders = require("telescope.finders")
    local builtin = require("telescope.builtin")
    local lga_actions = require("telescope-live-grep-args.actions")
    local lga_helpers = require("telescope-live-grep-args.helpers")

    -- helpers
    local function ensure_quoted(term)
      if term:match('^".*"$') then
        return term
      end
      return lga_helpers.quote(term)
    end

    -- I want to be able to search in particular directories and/or files, so I use
    -- "term" --iglob **/*<DIR>*/**/*<FILE>*
    -- Uses --iglob (case-insensitive glob) so path/file matching ignores case.
    -- The cursor gets placed at the DIR spot.
    local GLOB_HEAD = "**/*" -- DIR fragment goes right after this, at the cursor
    local GLOB_TAIL = "*/**/*" .. "*" -- FILE fragment goes between these, before the final *

    local function apply_glob(picker, exclude)
      if not picker then
        return
      end
      local prompt = vim.trim(picker:_get_prompt())
      -- quote prompt only if it is the first glob
      local base = prompt:find("--iglob", 1, true) and prompt or ensure_quoted(prompt)
      local before = base .. " --iglob " .. (exclude and "!" or "") .. GLOB_HEAD
      picker:set_prompt(before .. GLOB_TAIL)
      local col = #picker.prompt_prefix + #before
      vim.schedule(function()
        pcall(vim.api.nvim_win_set_cursor, picker.prompt_win, { 1, col })
      end)
    end

    local function glob_action(exclude)
      return function(prompt_bufnr)
        apply_glob(action_state.get_current_picker(prompt_bufnr), exclude)
      end
    end

    -- Drop current (or multi-selected) results from the picker list.
    -- delete_selection only works for static finders (finder.results).
    -- Async pickers (live_grep, etc.) have no results table — freeze the
    -- current manager entries into a table finder, minus the dropped ones.
    local function drop_result(prompt_bufnr)
      local picker = action_state.get_current_picker(prompt_bufnr)

      if picker.finder.results then
        picker:delete_selection(function()
          return true
        end)
        return
      end

      local drop = {}
      local multi = picker:get_multi_selection()
      if not vim.tbl_isempty(multi) then
        for _, entry in ipairs(multi) do
          drop[entry] = true
        end
      else
        local selection = action_state.get_selected_entry()
        if not selection then
          return
        end
        drop[selection] = true
      end

      local kept = {}
      for entry in picker.manager:iter() do
        if not drop[entry] then
          kept[#kept + 1] = entry
        end
      end

      -- Keep the same results-row after freeze (same trick as delete_selection).
      local original_selection_strategy = picker.selection_strategy
      picker.selection_strategy = "row"

      picker:refresh(
        finders.new_table({
          results = kept,
          entry_maker = function(entry)
            return entry
          end,
        }),
        { reset_prompt = false }
      )

      vim.defer_fn(function()
        picker.selection_strategy = original_selection_strategy
      end, 50)
    end

    -- Center the opened line (esp. near EOF, where a plain jump hugs the bottom).
    local function select_and_center(select_fn)
      return function(prompt_bufnr)
        select_fn(prompt_bufnr)
        vim.schedule(function()
          vim.cmd("normal! zz")
        end)
      end
    end

    telescope.setup({
      defaults = {
        path_display = { "truncate" },
        vimgrep_arguments = {
          "rg",
          "--color=never",
          "--no-heading",
          "--with-filename",
          "--line-number",
          "--column",
          "--smart-case",
        },
        mappings = {
          i = {
            ["<C-k>"] = actions.move_selection_previous, -- move to prev result
            ["<C-j>"] = actions.move_selection_next, -- move to next result
            -- selected if any, else all → new qflist
            ["<C-q>"] = actions.smart_send_to_qflist + actions.open_qflist,
            -- selected if any, else all → append to current qflist
            ["<C-a>"] = actions.smart_add_to_qflist + actions.open_qflist,
            -- override defaults: C-x was hsplit; C-s free → hsplit like C-w s
            ["<C-x>"] = drop_result,
            ["<CR>"] = select_and_center(actions.select_default),
            ["<C-s>"] = select_and_center(actions.select_horizontal),
            ["<C-v>"] = select_and_center(actions.select_vertical),
            ["<C-t>"] = select_and_center(actions.select_tab),
          },
          n = {
            ["<C-q>"] = actions.smart_send_to_qflist + actions.open_qflist,
            ["<C-a>"] = actions.smart_add_to_qflist + actions.open_qflist,
            ["<C-x>"] = drop_result,
            ["<CR>"] = select_and_center(actions.select_default),
            ["<C-s>"] = select_and_center(actions.select_horizontal),
            ["<C-v>"] = select_and_center(actions.select_vertical),
            ["<C-t>"] = select_and_center(actions.select_tab),
          },
        },
      },
      extensions = {
        -- Lets you type ripgrep args (e.g. -g) inline in the prompt
        live_grep_args = {
          auto_quoting = true,
          mappings = {
            i = {
              -- quote the current prompt (handy when the term has spaces)
              ["<C-'>"] = lga_actions.quote_prompt(),
              -- include glob: "term" --iglob **/*<cursor>*/**/*<file>*
              ["<C-g>"] = glob_action(false),
              -- exclude glob: same, but ` --iglob !...`
              ["<C-e>"] = glob_action(true),
            },
          },
        },
      },
    })

    telescope.load_extension("fzf")
    telescope.load_extension("live_grep_args")

    -- set keymaps
    local keymap = vim.keymap -- for conciseness

    -- Telescope: C-v vertical, C-s horizontal, C-t tab; C-x drops result from picker

    keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Fuzzy find files in cwd" })
    keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Fuzzy find in open buffers" })
    keymap.set("n", "<leader>fr", builtin.resume, { desc = "Resume last search" })
    keymap.set("n", "<leader>fo", builtin.oldfiles, { desc = "Fuzzy find recent files" })

    keymap.set("n", "<leader>fg", telescope.extensions.live_grep_args.live_grep_args, { desc = "Find string in cwd" })
    keymap.set("n", "<leader>fw", function()
      telescope.extensions.live_grep_args.live_grep_args({
        default_text = vim.fn.expand("<cword>"),
      })
      vim.schedule(function()
        apply_glob(action_state.get_current_picker(vim.api.nvim_get_current_buf()), false)
      end)
    end, { desc = "Find string under cursor in cwd" })

    -- find all
    keymap.set("n", "<leader>fa", function()
      telescope.extensions.live_grep_args.live_grep_args({
        additional_args = { "--hidden" },
        prompt_title = "Find string in cwd (hidden)",
      })
    end, { desc = "Find string in cwd (hidden)" })

    -- find in the current folder
    keymap.set("n", "<leader>fd", function()
      builtin.live_grep({
        cwd = vim.fn.expand("%:p:h"),
        prompt_title = "Find string in current folder",
      })
    end, { desc = "Find string in current folder" })

    keymap.set("n", "<leader>/", builtin.current_buffer_fuzzy_find, { desc = "Fuzzy find in current buffer" })

    -- fuzzy find in the current file, seeded with the word under the cursor
    keymap.set("n", "<leader>*", function()
      builtin.current_buffer_fuzzy_find({
        default_text = vim.fn.expand("<cword>"),
      })
    end, { desc = "Fuzzy find in current buffer with word under cursor" })

    keymap.set("n", "<leader>ft", vim.cmd.TodoTelescope, { desc = "Find todos" })

    -- Next `link` at/after the cursor: current line first, then the following lines.
    -- A span whose closing backtick is under the cursor is skipped, so that after
    -- <leader>fl parks the cursor there, the next call moves on to the next link.
    -- Returns text, line (1-based), col of the closing backtick (1-based).
    local function next_backtick_span()
      local cur_lnum = vim.fn.line(".")
      local cur_col = vim.fn.col(".")
      for lnum = cur_lnum, vim.fn.line("$") do
        local line = vim.fn.getline(lnum)
        local init = 1
        while true do
          local s, e, text = line:find("`([^`]+)`", init)
          if not s then
            break
          end
          if lnum ~= cur_lnum or e > cur_col then
            return text, lnum, e
          end
          init = e + 1
        end
      end
      return nil
    end

    -- Jump to where code should open: another file window in this tab if there is
    -- one (skipping nvim-tree, Trouble, terminals, ... via buftype), else the other
    -- tab. With one window and one tab this is a no-op.
    local function goto_other_place()
      local cur = vim.api.nvim_get_current_win()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if win ~= cur and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
          vim.api.nvim_set_current_win(win)
          return
        end
      end
      vim.cmd("tabnext")
    end

    -- Review workflow: the plan (with `path:line` links) lives in one pane or tab,
    -- the code in the other. Yank the next link, go to the other place, and find it.
    -- find_files parses `path:line` itself and jumps to the line on <CR>.
    keymap.set("n", "<leader>fl", function()
      local link, lnum, col = next_backtick_span()
      if not link then
        vim.notify("No `link` found after the cursor", vim.log.levels.WARN)
        return
      end
      vim.fn.setreg('"', link)
      vim.api.nvim_win_set_cursor(0, { lnum, col - 1 })
      goto_other_place()
      builtin.find_files({ default_text = link })
    end, { desc = "Find next `link` in the other pane/tab" })

  end,
}