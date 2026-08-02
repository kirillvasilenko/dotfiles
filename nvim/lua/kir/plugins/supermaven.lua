return {
  "supermaven-inc/supermaven-nvim",
  event = "InsertEnter",
  config = function()
    require("supermaven-nvim").setup({
      -- Defaults: ghost text, <Tab> accept, <C-]> clear, <C-j> accept word.
    })
  end,
}
