#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid

if [ "${RESET_APP_CACHE_ON_BOOT:-false}" = "true" ]; then
  rm -rf /app/tmp/cache/*
fi

LOCKFILE_HASH_FILE=/app/node_modules/.pnpm-lock.hash
CURRENT_LOCKFILE_HASH="$(sha256sum /app/pnpm-lock.yaml | awk '{ print $1 }')"
INSTALLED_LOCKFILE_HASH=""

if [ -f "$LOCKFILE_HASH_FILE" ]; then
  INSTALLED_LOCKFILE_HASH="$(cat "$LOCKFILE_HASH_FILE")"
fi

if [ ! -x /app/node_modules/.bin/vite ] || [ "$CURRENT_LOCKFILE_HASH" != "$INSTALLED_LOCKFILE_HASH" ]; then
  pnpm install --frozen-lockfile
  echo "$CURRENT_LOCKFILE_HASH" > "$LOCKFILE_HASH_FILE"
fi

echo "Ready to run Vite development server."

exec "$@"
