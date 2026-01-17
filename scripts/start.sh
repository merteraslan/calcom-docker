#!/bin/sh
set -e
set -x

# Replace the statically built BUILT_NEXT_PUBLIC_WEBAPP_URL with run-time NEXT_PUBLIC_WEBAPP_URL
# NOTE: if these values are the same, this will be skipped.
scripts/replace-placeholder.sh "$BUILT_NEXT_PUBLIC_WEBAPP_URL" "$NEXT_PUBLIC_WEBAPP_URL"

# Handle DATABASE_HOST being just a hostname or host:port
HOST=${DATABASE_HOST:-database}
if ! echo "$HOST" | grep -q ":"; then
  HOST="$HOST:5432"
fi

# Wait for database with a 60s timeout. 
# -t 60: Wait up to 60 seconds
# --strict: Fail strictly if it doesn't come up
scripts/wait-for-it.sh "$HOST" -t 60 -- echo "database is up"
npx prisma migrate deploy --schema /calcom/packages/prisma/schema.prisma
npx ts-node --transpile-only /calcom/scripts/seed-app-store.ts

# Copy app-store static files (icons) to public folder
# This is needed because public/app-store is gitignored
cd /calcom/apps/web && node scripts/copy-app-store-static.js && cd /calcom

yarn start

