start:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.dev.yml up

stop:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.dev.yml down

logs:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.dev.yml logs -f

config:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.dev.yml config

start-prod:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.prod.yml up

stop-prod:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.prod.yml down

config-prod:
	COMPOSE_PROJECT_NAME=gratheon-clickstack docker compose -f docker-compose.prod.yml config
