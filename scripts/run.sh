#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

function pretty_print {
  printf "  \033[36m%-30s\033[0m %s\n" "$1" "$2"
}

function print_group {
  local dir="$1"
  local label="$2"

  local has_scripts=false
  for script in "$dir"/*.sh; do
    [ -f "$script" ] && has_scripts=true && break
  done
  $has_scripts || return

  printf "\033[1m%s\033[0m\n" "$label"
  for script in "$dir"/*.sh; do
    [ -f "$script" ] || continue
    name=$(basename "$script" .sh)
    desc=$(grep -m1 '^# @description' "$script" | sed 's/^# @description //')
    pretty_print "$name" "$desc"
  done
  echo ""
}

function list {
  echo "Available commands:"
  echo ""

  # Global commands first
  print_group "$SCRIPT_DIR/global" "Global"

  # Then every other subfolder alphabetically
  for dir in "$SCRIPT_DIR"/*/; do
    [ -d "$dir" ] || continue
    folder=$(basename "$dir")
    [ "$folder" = "global" ] && continue
    print_group "$dir" "$folder"
  done
}

function find_script {
  local cmd="$1"

  # Search global first, then other folders
  if [ -f "$SCRIPT_DIR/global/$cmd.sh" ]; then
    echo "$SCRIPT_DIR/global/$cmd.sh"
    return
  fi

  for dir in "$SCRIPT_DIR"/*/; do
    [ -d "$dir" ] || continue
    if [ -f "$dir/$cmd.sh" ]; then
      echo "$dir/$cmd.sh"
      return
    fi
  done
}

command="$1"
shift 2>/dev/null

if [ -z "$command" ]; then
  list
  exit 0
fi

target=$(find_script "$command")

if [ -n "$target" ]; then
  exec bash "$target" "$@"
else
  echo "Unknown command: $command"
  echo ""
  list
  exit 1
fi
