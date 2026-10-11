#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [home-directory]" >&2
  exit 1
fi
target_home="${1:-$HOME}"
mkdir -p "$target_home/.ssh"
chmod 700 "$target_home/.ssh"
socket="$target_home/.ssh/ssh_auth_sock"
if [[ -e "$socket" && ! -L "$socket" ]]; then
  echo "error: $socket exists and is not a symlink" >&2
  exit 1
fi

rc="$target_home/.ssh/rc"
if [[ ! -e "$rc" ]]; then
  cat > "$rc" <<'SH'
#!/bin/sh
# A user rc replaces sshd's automatic X11 cookie setup.
if [ -n "$DISPLAY" ] && read -r proto cookie; then
  case "$DISPLAY" in
    localhost:*) display="unix:${DISPLAY#localhost:}" ;;
    *) display="$DISPLAY" ;;
  esac
  printf 'add %s %s %s\n' "$display" "$proto" "$cookie" | xauth -q -
fi
SH
fi
if ! grep -Fq '# dotfiles: stable SSH agent socket' "$rc"; then
  cat >> "$rc" <<'SH'

# dotfiles: stable SSH agent socket
if [ ! -S "$HOME/.ssh/ssh_auth_sock" ] && [ -S "${SSH_AUTH_SOCK:-}" ]; then
  ln -sfn "$SSH_AUTH_SOCK" "$HOME/.ssh/ssh_auth_sock"
fi
SH
fi
chmod 700 "$rc"

case "${SHELL:-/bin/bash}" in
  */zsh) shell_rc="$target_home/.zshrc" ;;
  *) shell_rc="$target_home/.bashrc" ;;
esac
line='if [ -S "$HOME/.ssh/ssh_auth_sock" ]; then export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"; fi'
if ! grep -Fxq "$line" "$shell_rc" 2>/dev/null; then
  printf '\n%s\n' "$line" >> "$shell_rc"
fi
echo 'SSH agent setup installed; reconnect with agent forwarding to initialize the link.'
