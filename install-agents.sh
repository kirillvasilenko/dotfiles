#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ -z "$1" ]; }; then
  echo "Usage: $0 [home-directory]" >&2
  exit 1
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
target_home="${1:-$HOME}"
codex_dir="$target_home/.codex"
claude_dir="$target_home/.claude"
if [ "$#" -eq 0 ]; then
  codex_dir="${CODEX_HOME:-$codex_dir}"
  claude_dir="${CLAUDE_CONFIG_DIR:-$claude_dir}"
fi

sources=("$repo_dir/agents/AGENTS.md" "$repo_dir/agents/AGENTS.md" "$repo_dir/agents/AGENTS.md")
destinations=("$codex_dir/AGENTS.md" "$claude_dir/CLAUDE.md" "$target_home/.gemini/GEMINI.md")
skill_dirs=("$target_home/.agents/skills" "$claude_dir/skills")

for skill_file in "$repo_dir"/skills/*/SKILL.md; do
  [ -f "$skill_file" ] || continue
  skill_dir="$(dirname "$skill_file")"
  for destination in "${skill_dirs[@]}"; do
    sources+=("$skill_dir")
    destinations+=("$destination/$(basename "$skill_dir")")
  done
done

# Keep skill roots separate from the repository so agent-managed downloads stay out of it.
for directory in "${skill_dirs[@]}"; do
  if [ -L "$directory" ]; then
    echo "Refusing symlinked skills directory: $directory. Use a real directory with per-skill links." >&2
    exit 1
  fi
done

for i in "${!destinations[@]}"; do
  source_path="${sources[$i]}"
  destination="${destinations[$i]}"
  if [ ! -e "$source_path" ]; then
    echo "Missing source: $source_path" >&2
    exit 1
  fi
  if [ -e "$destination" ] || [ -L "$destination" ]; then
    if [ ! -L "$destination" ] || [ ! "$destination" -ef "$source_path" ]; then
      echo "Conflict: $destination. Move it aside or merge its contents before re-running." >&2
      exit 1
    fi
  fi
  directory="$(dirname "$destination")"
  while [ ! -d "$directory" ]; do
    if [ -e "$directory" ] || [ -L "$directory" ]; then
      echo "Not a directory: $directory" >&2
      exit 1
    fi
    directory="$(dirname "$directory")"
  done
done

for i in "${!destinations[@]}"; do
  destination="${destinations[$i]}"
  if [ -L "$destination" ]; then
    echo "Already linked: $destination"
    continue
  fi
  mkdir -p "$(dirname "$destination")"
  ln -s "${sources[$i]}" "$destination"
  echo "Linked: $destination → ${sources[$i]}"
done

echo "Done! Restart your agents to load the rules and skills."
