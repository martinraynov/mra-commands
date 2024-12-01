#!/bin/bash

### Functions

# Pretty print a message
function pretty_print {
  printf "\033[36m%-30s\033[0m %s\n" "$1" "$2"
}
# List all available commands
function list {
  echo "List all available commands"
  pretty_print "zsh_reload" "Reload zsh"
  pretty_print "gprune" "Prune merged git branches"
  pretty_print "dprune" "Prune docker system"
}

# Reload zsh
function zsh_reload {
  # Delete the completion cache
  # rm "$ZSH_COMPDUMP"
  # Restart the zsh session
  exec zsh
}

# Prune git branches
function gprune {
  echo "Pruning merged git branches"
  (git branch --merged=main && git branch -d $(git branch --merged=main | grep -v main) && git fetch --prune)
}

function dprune {
  echo "Pruning docker system"
  (docker system prune -a && docker volume prune --force && docker network prune --force && docker image prune --force)
}

################################################
# Check wich command to run (param to be passed)
case $1 in
  "zsh_reload")
    zsh_reload
    ;;
  "gprune")
    gprune
    ;;
  "dprune")
    dprune
    ;;
  *)
    list
    ;;
esac
