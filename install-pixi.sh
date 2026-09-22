#!/usr/bin/env bash

set -e

echo "Installing pixi tools (symlink mode)..."

PIXI_HOME="${PIXI_HOME:-$HOME/.pixi}"
MANIFEST="$PIXI_HOME/manifests/pixi-global.toml"
REPO_MANIFEST="$(pwd)/pixi/pixi-global.toml"

# pixi itself: one static binary in ~/.pixi/bin. PIXI_NO_PATH_UPDATE keeps the
# installer from editing shell rc files; PATH is handled below.
if [ ! -x "$PIXI_HOME/bin/pixi" ]; then
  echo "Installing pixi to $PIXI_HOME/bin..."
  curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash
fi

mkdir -p "$PIXI_HOME/manifests"

# Backup existing manifest if it's not already a symlink
if [ -e "$MANIFEST" ] && [ ! -L "$MANIFEST" ]; then
  echo "Backing up existing manifest to ${MANIFEST}.backup"
  mv "$MANIFEST" "${MANIFEST}.backup"
fi

# Remove existing symlink (if any)
if [ -L "$MANIFEST" ]; then
  rm "$MANIFEST"
fi

# Create symlink
ln -s "$REPO_MANIFEST" "$MANIFEST"

echo "Symlink created:"
echo "$MANIFEST → $REPO_MANIFEST"

# Install exactly what the manifest lists (and remove what it no longer lists).
"$PIXI_HOME/bin/pixi" global sync

case ":$PATH:" in
  *":$PIXI_HOME/bin:"*) ;;
  *)
    echo "WARNING: $PIXI_HOME/bin is not on PATH. Add to ~/.bashrc:"
    echo '  export PATH="$HOME/.pixi/bin:$HOME/.local/bin:$HOME/dotfiles/bin:$PATH"'
    ;;
esac

echo "Done!"
echo "Edit pixi/pixi-global.toml and run 'pixi global sync' to change tools."
