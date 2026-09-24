-- Sidekick, used only as a bridge from Neovim to AI agents (Claude Code, Codex)
-- running in tmux. An agent lives in a real tmux pane (bottom half), so it
-- survives Neovim restarts and is reached with the usual tmux/vim-tmux-navigator
-- keys. Sending pastes text into that pane; there is no MCP channel back, so no
-- native diffs.
-- NES (Copilot next-edit suggestions) is off: no copilot-language-server here.

-- Starts the agent in the tmux split (or attaches to a running one) and moves
-- the tmux focus there. Sidekick's own `focus` only covers panes it shows
-- inside Neovim; for a tmux pane "attach" only records the send target, so
-- an agent picked from another session/window is pulled into this window
-- (join-pane) below Neovim. Hide/close it with tmux.
local function open_agent(name)
  require("sidekick.cli.state").with(function(state)
    local pane = state.session and state.session.tmux_pane_id
    if not pane then
      return
    end
    local function tmux(...)
      return vim.trim(vim.fn.system({ "tmux", ... }))
    end
    local here = tmux("display", "-p", "#{window_id}")
    local there = tmux("display", "-p", "-t", pane, "#{window_id}")
    if there ~= here then
      tmux("join-pane", "-v", "-l", "50%", "-s", pane, "-t", vim.env.TMUX_PANE)
    end
    tmux("select-pane", "-t", pane)
  end, { filter = { name = name }, attach = true, show = true })
end

return {
  "folke/sidekick.nvim",
  opts = {
    nes = { enabled = false },
    cli = {
      mux = {
        backend = "tmux",
        enabled = true,
        -- Real tmux split below Neovim, half the window.
        create = "split",
        split = { vertical = false, size = 0.5 },
      },
    },
  },
  keys = {
    -- No rhs: only labels the <leader>a prefix in the which-key popup.
    { "<leader>a", nil, desc = "AI agents" },
    { "<leader>ac", function() open_agent("claude") end, desc = "Open Claude pane" },
    { "<leader>ax", function() open_agent("codex") end, desc = "Open Codex pane" },
    -- Pastes "@path :L1:C1-L2:C2" (no code) into the attached agent's prompt;
    -- asks which one when several are attached, or which to start when none is.
    {
      "<leader>as",
      function()
        require("sidekick.cli").send({ msg = "{this}" })
      end,
      mode = { "n", "x" },
      desc = "Send location to agent",
    },
    {
      "<leader>ap",
      function()
        require("sidekick.cli").prompt()
      end,
      mode = { "n", "x" },
      desc = "Agent prompt picker",
    },
  },
}
