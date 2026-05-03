start:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.dev.yml up

stop:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.dev.yml down

logs:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.dev.yml logs -f

config:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.dev.yml config

set-dev-ingest-key:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.dev.yml exec -T mongo mongosh --quiet hyperdx --eval 'db.teams.updateMany({}, { $set: { apiKey: "local-gratheon-clickstack" } })'
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.dev.yml restart otel-collector

start-prod:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.prod.yml up

stop-prod:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.prod.yml down

config-prod:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.prod.yml config
