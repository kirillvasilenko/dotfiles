#!/usr/bin/env bash

set -euo pipefail

echo "Installing Homebrew tools from brew/Brewfile..."

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is not installed: https://brew.sh"
  exit 1
fi

brewfile="$(cd "$(dirname "$0")" && pwd)/brew/Brewfile"
brew bundle --file="$brewfile"

python_formula="$(brew bundle list --brews --file="$brewfile" | grep '^python@')"
python_prefix="$(brew --prefix "$python_formula")"
mkdir -p "$HOME/.local/bin"
for command in python3 pip3; do
  link="$HOME/.local/bin/$command"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "Refusing to replace $link: it is not a symlink." >&2
    exit 1
  fi
  ln -sfn "$python_prefix/libexec/bin/$command" "$link"
done

echo "Done!"
echo "Edit brew/Brewfile and re-run to change tools."
