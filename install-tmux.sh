#!/usr/bin/env bash

set -e

echo "Installing tmux config (symlink mode)..."

CONF="$HOME/.tmux.conf"
REPO_CONF="$(pwd)/tmux/.tmux.conf"
TPM_DIR="$HOME/.tmux/plugins/tpm"

# Backup existing config if it's not already a symlink
if [ -e "$CONF" ] && [ ! -L "$CONF" ]; then
  echo "Backing up existing config to ~/.tmux.conf.backup"
  mv "$CONF" "${CONF}.backup"
fi

# Remove existing symlink (if any)
if [ -L "$CONF" ]; then
  rm "$CONF"
fi

# Create symlink
ln -s "$REPO_CONF" "$CONF"

echo "Symlink created:"
echo "$CONF → $REPO_CONF"

# TPM (tmux plugin manager): https://github.com/tmux-plugins/tpm
if [ -d "$TPM_DIR/.git" ]; then
  echo "TPM already present, updating..."
  git -C "$TPM_DIR" pull --ff-only
else
  echo "Cloning TPM to $TPM_DIR..."
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
fi

# Install the @plugin entries from .tmux.conf now, so <prefix>I is not needed
# on a fresh machine. TPM's installer aborts unless the config sources tpm.
if grep -q 'plugins/tpm/tpm' "$REPO_CONF"; then
  "$TPM_DIR/bin/install_plugins"
else
  echo "Skipping plugin install: $REPO_CONF does not load TPM yet."
  echo "Add at the end of it (after the @plugin lines):"
  echo "  run '~/.tmux/plugins/tpm/tpm'"
fi

echo "Done!"
echo "Reload a running server with '<prefix>r' (or 'tmux source-file ~/.tmux.conf')."
