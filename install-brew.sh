#!/usr/bin/env bash

set -e

echo "Installing Homebrew tools from brew/Brewfile..."

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is not installed: https://brew.sh"
  exit 1
fi

brew bundle --file="$(pwd)/brew/Brewfile"

echo "Done!"
echo "Edit brew/Brewfile and re-run to change tools."
