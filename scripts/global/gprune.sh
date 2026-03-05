#!/bin/bash
# @description Prune merged git branches

echo "Pruning merged git branches"

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "Error: Not in a git repository"
  exit 1
fi

merged=$(git branch --merged=main | grep -v -E '^\*? *main$' | sed 's/^[* ]*//')
if [ -n "$merged" ]; then
  echo "$merged" | xargs git branch -d
fi
git fetch --prune
