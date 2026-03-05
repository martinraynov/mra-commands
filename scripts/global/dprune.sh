#!/bin/bash
# @description Prune docker system

echo "Pruning docker system"
docker system prune -a \
  && docker volume prune --force \
  && docker network prune --force \
  && docker image prune --force
