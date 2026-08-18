#!/bin/bash
# @description Start Cursor in the core folder

ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

load_dlp_cursor_core_dir() {
  if [ -n "${DLP_CURSOR_CORE_DIR:-}" ]; then
    printf '%s\n' "$DLP_CURSOR_CORE_DIR"
    return 0
  fi

  if [ ! -f "$ZSHRC" ]; then
    return 1
  fi

  local line value
  line=$(grep -E '^[[:space:]]*export[[:space:]]+DLP_CURSOR_CORE_DIR=' "$ZSHRC" | tail -n1)
  [ -n "$line" ] || return 1

  value=$(sed -E 's/^[[:space:]]*export[[:space:]]+DLP_CURSOR_CORE_DIR="?([^"]*)"?/\1/' <<< "$line")
  value="${value/#\~/$HOME}"
  [ -n "$value" ] || return 1

  printf '%s\n' "$value"
}

CORE_DIR=$(load_dlp_cursor_core_dir) || CORE_DIR=""

if [ -z "$CORE_DIR" ]; then
  if [ ! -t 0 ]; then
    echo "DLP_CURSOR_CORE_DIR is not set." >&2
    echo "Add to $ZSHRC:" >&2
    echo '  export DLP_CURSOR_CORE_DIR="/path/to/dlp-cursor-core"' >&2
    exit 1
  fi

  echo "DLP_CURSOR_CORE_DIR is not set."
  read -r -p "Enter path to dlp-cursor-core: " CORE_DIR
  CORE_DIR="${CORE_DIR/#\~/$HOME}"
  CORE_DIR="${CORE_DIR%/}"

  if [ -z "$CORE_DIR" ]; then
    echo "No path provided." >&2
    exit 1
  fi

  if [ ! -d "$CORE_DIR" ]; then
    echo "Directory does not exist: $CORE_DIR" >&2
    exit 1
  fi

  export_line="export DLP_CURSOR_CORE_DIR=\"$CORE_DIR\""
  read -r -p "Add this to $ZSHRC for future sessions? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    if grep -q 'DLP_CURSOR_CORE_DIR' "$ZSHRC" 2>/dev/null; then
      echo "DLP_CURSOR_CORE_DIR is already defined in $ZSHRC — update it manually if needed."
    else
      {
        echo ""
        echo "# dlp-cursor-core path (added by mra cursor)"
        echo "$export_line"
      } >> "$ZSHRC"
      echo "Added to $ZSHRC"
    fi
  fi
fi

if [ ! -d "$CORE_DIR" ]; then
  echo "Directory does not exist: $CORE_DIR" >&2
  exit 1
fi

echo "Starting Cursor in $CORE_DIR"
exec cursor "$CORE_DIR"
