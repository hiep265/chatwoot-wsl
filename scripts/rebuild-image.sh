#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.production.yaml}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-chatwootprod}"

cd "$ROOT_DIR"

echo "Rebuilding Chatwoot production image using $COMPOSE_FILE for project $COMPOSE_PROJECT_NAME..."
docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE" build rails sidekiq

echo "Image rebuild finished."
