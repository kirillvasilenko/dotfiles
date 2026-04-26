
-- Telescope
local telescope = require("telescope")
local builtin = require("telescope.builtin")

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
})

-- In the search window you can ctrl+v/x/t - open the file in a vertical/horisontal split/new tab
vim.keymap.set("n", "<leader>ff", builtin.find_files)
vim.keymap.set("n", "<leader>fb", builtin.buffers)
vim.keymap.set("n", "<leader>fr", builtin.resume)
-- find the word under the cursor
vim.keymap.set("n", "<leader>fw", builtin.grep_string)
vim.keymap.set("n", "<leader>fg", builtin.live_grep)
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

-- Lsp integration
vim.keymap.set("n", "gd", builtin.lsp_definitions)
vim.keymap.set("n", "gr", builtin.lsp_references)
vim.keymap.set("n", "gi", builtin.lsp_implementations)
vim.keymap.set("n", "gy", builtin.lsp_type_definitions)

