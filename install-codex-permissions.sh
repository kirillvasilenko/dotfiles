#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ -z "$1" ]; }; then
  echo "Usage: $0 [home-directory]" >&2
  exit 1
fi

target_home="${1:-$HOME}"
codex_dir="$target_home/.codex"
if [ "$#" -eq 0 ]; then
  codex_dir="${CODEX_HOME:-$codex_dir}"
fi

config="$codex_dir/config.toml"
if [ -L "$config" ]; then
  echo "Edit the symlinked config directly: $config" >&2
  exit 1
fi
if grep -Fqx '# dotfiles: Codex permissions' "$config" 2>/dev/null; then
  echo "Codex permissions already installed: $config"
  exit 0
fi
if grep -Eq "^[[:space:]]*[\"']?(approval_policy|approvals_reviewer|sandbox_mode|sandbox_workspace_write|default_permissions)[\"']?[[:space:].=]|^[[:space:]]*\[[[:space:]]*[\"']?sandbox_workspace_write" "$config" 2>/dev/null; then
  echo "Permission settings already exist in $config. Update them using the README block." >&2
  exit 1
fi

mkdir -p "$codex_dir"
temporary="$(mktemp "$codex_dir/.config.XXXXXX")"
trap 'rm -f "$temporary"' EXIT
cat > "$temporary" <<EOF
# dotfiles: Codex permissions
approval_policy = "on-request"
approvals_reviewer = "auto_review"
sandbox_mode = "workspace-write"
sandbox_workspace_write.writable_roots = ["$target_home/junk", "$target_home/dotfiles", "$target_home/.ya", "$target_home/slice"]

EOF
if [ -f "$config" ]; then
  cat "$config" >> "$temporary"
fi
mv "$temporary" "$config"
echo "Codex permissions installed. Restart Codex to use them."
