#!/bin/sh

set -x

# Remove a potentially pre-existing server.pid for Rails.
rm -rf /app/tmp/pids/server.pid

if [ "${RESET_APP_CACHE_ON_BOOT:-false}" = "true" ]; then
  rm -rf /app/tmp/cache/*
fi

echo "Waiting for postgres to become ready...."

# Let DATABASE_URL env take presedence over individual connection params.
# This is done to avoid printing the DATABASE_URL in the logs
$(docker/entrypoints/helpers/pg_database_url.rb)
PG_READY="pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USERNAME"

until $PG_READY
do
  sleep 2;
done

echo "Database ready to accept connections."

# Install missing gems only when the lockfile and bundle state require it.
bundle check || bundle install

# Execute the main process of the container
exec "$@"
