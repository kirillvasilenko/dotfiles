
-- Telescope
local telescope = require("telescope")
local builtin = require("telescope.builtin")
local lga_actions = require("telescope-live-grep-args.actions")

-- Setup
telescope.setup({
  defaults = {
    vimgrep_arguments = {
      "rg",
      "--color=never",
      "--no-heading",
      "--with-filename",
      "--line-number",
      "--column",
      "--smart-case",
    },
  },
  extensions = {
    -- Lets you type ripgrep args (e.g. -g) inline in the prompt,
    -- like VS Code's "files to include/exclude". See <leader>fg below.
    live_grep_args = {
      -- false: the search term does NOT need quotes, so `foo -g *.lua` works.
      -- Only quote the term when it contains spaces, e.g. `"foo bar" -g *.lua`.
      auto_quoting = true,
      mappings = {
        i = {
          -- quote the current prompt (handy when the term has spaces)
          ["<C-k>"] = lga_actions.quote_prompt(),
          -- prime an include glob:  <term> -g <cursor>
          ["<C-g>"] = lga_actions.quote_prompt({ postfix = " -g " }),
          -- prime an exclude glob:  <term> -g !<cursor>
          ["<C-e>"] = lga_actions.quote_prompt({ postfix = " -g !" }),
        },
      },
    },
  },
})

telescope.load_extension("live_grep_args")

-- In the search window you can ctrl+v/x/t - open the file in a vertical/horisontal split/new tab
vim.keymap.set("n", "<leader>ff", builtin.find_files)
vim.keymap.set("n", "<leader>fb", builtin.buffers)
vim.keymap.set("n", "<leader>fr", builtin.resume)
-- find the word under the cursor
vim.keymap.set("n", "<leader>fw", builtin.grep_string)
vim.keymap.set("n", "<leader>fg", telescope.extensions.live_grep_args.live_grep_args)
-- find all
vim.keymap.set("n", "<leader>fa", function()
  builtin.live_grep({
    additional_args = function()
      return { "--hidden" }
    end,
    prompt_title = "Live Grep Hidden",
  })
end)
-- find in the current folder
vim.keymap.set("n", "<leader>fd", function()
  builtin.live_grep({
    cwd = vim.fn.expand("%:p:h"),
    prompt_title = "Live Grep Current Dir",
  })
end)
vim.keymap.set("n", "<leader>/", builtin.current_buffer_fuzzy_find)
-- fuzzy find in the current file, seeded with the word under the cursor
vim.keymap.set("n", "<leader>*", function()
  builtin.current_buffer_fuzzy_find({
    default_text = vim.fn.expand("<cword>"),
  })
end)
