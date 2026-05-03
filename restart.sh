#!/bin/sh
set -eu

cd /www/clickstack/

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

COMPOSE_PROJECT_NAME=gratheon-clickstack compose -f docker-compose.prod.yml pull
COMPOSE_PROJECT_NAME=gratheon-clickstack compose -f docker-compose.prod.yml up -d
