#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [rc-file]" >&2
  exit 1
fi

if [ "$#" -eq 1 ]; then
  rc_file="$1"
else
  case "${SHELL:-/bin/bash}" in
    */bash) rc_file="$HOME/.bashrc" ;;
    */zsh) rc_file="${ZDOTDIR:-$HOME}/.zshrc" ;;
    *)
      echo "Unsupported shell: $SHELL. Pass a Bash or Zsh rc file explicitly." >&2
      exit 1
      ;;
  esac
fi

path_line='export PATH="$HOME/.pixi/bin:$HOME/.local/bin:$HOME/dotfiles/bin:$PATH"'

mkdir -p "$(dirname "$rc_file")"
if [ -f "$rc_file" ] && grep -Fxq -- "$path_line" "$rc_file"; then
  echo "PATH is already configured in $rc_file"
else
  printf '\n# User tools and dotfiles helpers\n%s\n' "$path_line" >> "$rc_file"
  echo "Added PATH to $rc_file"
fi

printf 'To apply in your current shell, run: source %q\n' "$rc_file"
