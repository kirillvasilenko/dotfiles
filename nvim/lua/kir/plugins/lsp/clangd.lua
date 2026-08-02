return {
  "p00f/clangd_extensions.nvim",
  dependencies = { "neovim/nvim-lspconfig" },
  config = function()
    -- Defaults are fine; mason already enables clangd + cmp capabilities.
    require("clangd_extensions").setup({})

    local keymap = vim.keymap

    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("UserClangdConfig", { clear = true }),
      callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        if not client or client.name ~= "clangd" then
          return
        end

        local opts = { buffer = ev.buf, silent = true }

        -- Clangd-only keymaps (same gr* LSP family as lspconfig.lua)
        -- No Neovim default key for these — commands come from nvim-lspconfig /
        -- clangd_extensions; we just bind them.
        --
        -- key         source    our mapping                         previous behavior
        -- ----------  --------  ----------------------------------  ------------------------------------------
        -- grs         [custom]  :LspClangdSwitchSourceHeader         unbound (Vim: virtual-replace "s")
        -- grh         [custom]  type hierarchy (clangd_extensions)  unbound (Vim: virtual-replace "h")

        opts.desc = "Switch source/header"
        keymap.set("n", "grs", vim.cmd.LspClangdSwitchSourceHeader, opts)

        if client:supports_method("textDocument/prepareTypeHierarchy", ev.buf) then
          opts.desc = "Type hierarchy"
          keymap.set("n", "grh", vim.cmd.ClangdTypeHierarchy, opts)
        end
      end,
    })
  end,
}
