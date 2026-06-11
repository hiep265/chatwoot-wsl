#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.production.yaml}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-chatwootprod}"

cd "$ROOT_DIR"

echo "Building Chatwoot app image from current code using $COMPOSE_FILE for project $COMPOSE_PROJECT_NAME..."
docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" build rails sidekiq

echo "Recreating Chatwoot app containers from the freshly built image..."
docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" up -d --no-build --no-deps --force-recreate rails sidekiq

echo "Container recreate finished."
