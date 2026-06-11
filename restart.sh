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

if [ "${CLICKSTACK_PULL_IMAGES:-false}" = "true" ]; then
  COMPOSE_PROJECT_NAME=clickstack compose -f docker-compose.prod.yml pull
fi

COMPOSE_PROJECT_NAME=clickstack compose -f docker-compose.prod.yml up -d --scale dashboard-seed=0
COMPOSE_PROJECT_NAME=clickstack compose -f docker-compose.prod.yml run --rm dashboard-seed
