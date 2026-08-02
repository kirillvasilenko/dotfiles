return {
  "iamcco/markdown-preview.nvim",
  cmd = { "MarkdownPreview", "MarkdownPreviewStop", "MarkdownPreviewToggle" },
  ft = { "markdown" },
  -- Download the prebuilt server binary. `cd app && npm install` only pulls a
  -- subset of deps and breaks with "Cannot find module 'msgpack-lite'".
  build = function()
    vim.fn["mkdp#util#install"]()
  end,
  init = function()
    -- Work happens on a remote server, so launching a browser there is meaningless.
    vim.g.mkdp_browser = ""

    -- Serve the preview on a fixed, non-busy port so it can be SSH-forwarded to the
    -- Mac (e.g. `ssh -L 8899:localhost:8899 server`) and opened there.
    vim.g.mkdp_port = "8899"

    -- Don't auto-open a preview when entering a markdown buffer; start it manually.
    vim.g.mkdp_auto_start = 0
    vim.g.mkdp_auto_close = 0

    -- Echo the preview URL so it's clear what to open on the Mac.
    vim.g.mkdp_echo_preview_url = 1
  end,
  keys = {
    { "<leader>cp", "<cmd>MarkdownPreviewToggle<CR>", desc = "Markdown preview" },
  },
}
