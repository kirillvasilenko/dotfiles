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
            ["<C-l>"] = actions.send_selected_to_qflist + actions.open_qflist,
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
              ["<C-q>"] = lga_actions.quote_prompt(),
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

    -- In the search window you can ctrl+v/x/t - open the file in a vertical/horisontal split/new tab

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

  end,
}