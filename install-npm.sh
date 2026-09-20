#!/usr/bin/env bash

set -e

echo "Installing npm config (symlink mode)..."

NPMRC="$HOME/.npmrc"
REPO_NPMRC="$(pwd)/npm/.npmrc"

# Backup existing config if it's not already a symlink
if [ -e "$NPMRC" ] && [ ! -L "$NPMRC" ]; then
  echo "Backing up existing config to ~/.npmrc.backup"
  mv "$NPMRC" "${NPMRC}.backup"
fi

# Remove existing symlink (if any)
if [ -L "$NPMRC" ]; then
  rm "$NPMRC"
fi

# Create symlink
ln -s "$REPO_NPMRC" "$NPMRC"

echo "Symlink created:"
echo "$NPMRC → $REPO_NPMRC"

mkdir -p "$HOME/.local/bin"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "WARNING: ~/.local/bin is not on PATH; add it to your shell rc." ;;
esac

echo "Done!"
echo "Global prefix: $(npm config get prefix)"
