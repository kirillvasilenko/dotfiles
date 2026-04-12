#!/usr/bin/env bash

set -e

echo "Installing Neovim config (symlink mode)..."

CONFIG_DIR="$HOME/.config/nvim"
REPO_DIR="$(pwd)/nvim"

mkdir -p ~/.config

# Backup existing config if it's not already a symlink
if [ -e "$CONFIG_DIR" ] && [ ! -L "$CONFIG_DIR" ]; then
  echo "Backing up existing config to ~/.config/nvim.backup"
  mv "$CONFIG_DIR" "${CONFIG_DIR}.backup"
fi

# Remove existing symlink (if any)
if [ -L "$CONFIG_DIR" ]; then
  rm "$CONFIG_DIR"
fi

# Create symlink
ln -s "$REPO_DIR" "$CONFIG_DIR"

echo "Symlink created:"
echo "$CONFIG_DIR → $REPO_DIR"

echo "Done!"
echo "Run 'nvim' to start (plugins auto-install)."
