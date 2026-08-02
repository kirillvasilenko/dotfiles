return {
  "neovim/nvim-lspconfig",
  event = { "BufReadPre", "BufNewFile" },
  dependencies = {
    "hrsh7th/cmp-nvim-lsp",
    { "antosha417/nvim-lsp-file-operations", config = true },
    { "folke/neodev.nvim", opts = {} },
  },
  config = function()
    local telescope_builtin = require("telescope.builtin")
    local keymap = vim.keymap

    local function toggle_inlay_hints()
      local bufnr = vim.api.nvim_get_current_buf()
      local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr })
      vim.lsp.inlay_hint.enable(not enabled, { bufnr = bufnr })
    end

    vim.api.nvim_create_user_command("LspInlayHintToggle", toggle_inlay_hints, {
      desc = "Toggle LSP inlay hints for the current buffer",
    })

    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
      callback = function(ev)
        local opts = { buffer = ev.buf, silent = true }

        -- LSP keymaps cheat sheet (Neovim 0.11+)
        --   source:  [nvim] = Neovim LSP default | [custom] = we add it
        --   columns: key | source | our mapping | previous behavior (before us)
        --
        -- key         source    our mapping                         previous behavior
        -- ----------  --------  ----------------------------------  ------------------------------------------
        -- Navigation
        -- gd          [custom]  LSP definition (Telescope)          Vim: local declaration (text search)
        -- gD          [custom]  LSP declaration                     Vim: global declaration (text search)
        -- gri         [nvim]    LSP implementation (Telescope)      nvim: vim.lsp.buf.implementation()
        -- grt         [nvim]    (unchanged — native)                nvim: vim.lsp.buf.type_definition()
        -- gy          [custom]  LSP type definition (Telescope)     unbound (gt would be Vim: next tab)
        --
        -- Find usages / symbols
        -- grr         [nvim]    LSP references (Telescope)          nvim: vim.lsp.buf.references() → quickfix
        -- gO          [nvim]    document symbols (Telescope)        nvim: vim.lsp.buf.document_symbol()
        --
        -- Refactor / actions
        -- grn         [nvim]    (unchanged — native)                nvim: vim.lsp.buf.rename()
        -- gra         [nvim]    (unchanged — native)                nvim: vim.lsp.buf.code_action() (n/v)
        -- grx         [nvim]    (unchanged — native)                nvim: vim.lsp.codelens.run()
        --
        -- Info
        -- K           [nvim]    (unchanged — native)                nvim: vim.lsp.buf.hover()
        -- <C-s>       [nvim]    (unchanged — native)                nvim: vim.lsp.buf.signature_help() (i/s)
        --
        -- Diagnostics
        -- [d ]d       [nvim]    (unchanged — native)                nvim: prev / next diagnostic
        -- [D ]D       [nvim]    (unchanged — native)                nvim: first / last diagnostic
        -- <leader>d   [custom]  line diagnostics float              unbound
        -- <leader>D   [custom]  buffer diagnostics (Telescope)      unbound
        --
        -- Misc
        -- <leader>rs  [custom]  restart LSP client                  unbound
        -- grh         [custom]  toggle inlay hints                  unbound (Vim: virtual-replace "h")
        --             also: :LspInlayHintToggle

        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        if client and client:supports_method("textDocument/inlayHint", ev.buf) then
          vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
        end

        ----------------------------------------------------------------------
        -- Navigation
        ----------------------------------------------------------------------
        opts.desc = "Show LSP definitions"
        keymap.set("n", "gd", telescope_builtin.lsp_definitions, opts)

        opts.desc = "Go to declaration"
        keymap.set("n", "gD", vim.lsp.buf.declaration, opts)

        opts.desc = "Show LSP implementations"
        keymap.set("n", "gri", telescope_builtin.lsp_implementations, opts)

        opts.desc = "Show LSP type definitions"
        keymap.set("n", "gy", telescope_builtin.lsp_type_definitions, opts)

        ----------------------------------------------------------------------
        -- Find usages / symbols
        ----------------------------------------------------------------------
        opts.desc = "Show LSP references"
        keymap.set("n", "grr", telescope_builtin.lsp_references, opts)

        opts.desc = "Show document symbols"
        keymap.set("n", "gO", telescope_builtin.lsp_document_symbols, opts)

        ----------------------------------------------------------------------
        -- Diagnostics
        ----------------------------------------------------------------------
        opts.desc = "Show line diagnostics"
        keymap.set("n", "<leader>d", vim.diagnostic.open_float, opts)

        opts.desc = "Show buffer diagnostics"
        keymap.set("n", "<leader>D", function()
          telescope_builtin.diagnostics({ bufnr = 0 })
        end, opts)

        ----------------------------------------------------------------------
        -- Misc
        ----------------------------------------------------------------------
        opts.desc = "Restart LSP"
        keymap.set("n", "<leader>rs", vim.cmd.LspRestart, opts)

        opts.desc = "Toggle inlay hints"
        keymap.set("n", "grh", toggle_inlay_hints, opts)
      end,
    })
  end,
}
