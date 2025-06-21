# Stage 1: build the Cal.com app
FROM node:18 AS builder

WORKDIR /calcom

# Build-time args
ARG NEXT_PUBLIC_LICENSE_CONSENT
ARG NEXT_PUBLIC_WEBSITE_TERMS_URL
ARG NEXT_PUBLIC_WEBSITE_PRIVACY_POLICY_URL
ARG CALCOM_TELEMETRY_DISABLED
ARG DATABASE_URL
ARG NEXTAUTH_SECRET=secret
ARG CALENDSO_ENCRYPTION_KEY=secret
ARG MAX_OLD_SPACE_SIZE=4096
ARG NEXT_PUBLIC_API_V2_URL

# Export ENV for build
ENV NEXT_PUBLIC_WEBAPP_URL=http://NEXT_PUBLIC_WEBAPP_URL_PLACEHOLDER \
    NEXT_PUBLIC_API_V2_URL=$NEXT_PUBLIC_API_V2_URL \
    NEXT_PUBLIC_LICENSE_CONSENT=$NEXT_PUBLIC_LICENSE_CONSENT \
    NEXT_PUBLIC_WEBSITE_TERMS_URL=$NEXT_PUBLIC_WEBSITE_TERMS_URL \
    NEXT_PUBLIC_WEBSITE_PRIVACY_POLICY_URL=$NEXT_PUBLIC_WEBSITE_PRIVACY_POLICY_URL \
    CALCOM_TELEMETRY_DISABLED=$CALCOM_TELEMETRY_DISABLED \
    DATABASE_URL=$DATABASE_URL \
    DATABASE_DIRECT_URL=$DATABASE_URL \
    NEXTAUTH_SECRET=${NEXTAUTH_SECRET} \
    CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY} \
    NODE_OPTIONS=--max-old-space-size=${MAX_OLD_SPACE_SIZE} \
    BUILD_STANDALONE=true

# Copy only the files turbo prune needs
COPY calcom/package.json calcom/yarn.lock calcom/.yarnrc.yml calcom/playwright.config.ts calcom/turbo.json calcom/i18n.json ./
COPY calcom/.yarn ./.yarn
COPY calcom/apps/web ./apps/web
COPY calcom/apps/api/v2 ./apps/api/v2
COPY calcom/packages ./packages
COPY calcom/tests ./tests

# Enable Corepack & Yarn v3, then install deps
RUN corepack enable \
    && corepack prepare yarn@stable --activate \
    && yarn config set httpTimeout 1200000 \
    && npx turbo prune --scope=@calcom/web --scope=@calcom/trpc --docker \
    && yarn install --network-timeout 600000 --mode update-lockfile

# Build all pieces
RUN yarn workspace @calcom/trpc run build \
    && yarn --cwd packages/embeds/embed-core workspace @calcom/embed-core run build \
    && yarn --cwd apps/web workspace @calcom/web run build

# Clean up caches to slim the image
RUN rm -rf node_modules/.cache .yarn/cache apps/web/.next/cache

# Stage 2: assemble production files
FROM node:18 AS builder-two

WORKDIR /calcom
ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000
ENV NODE_ENV=production

# Copy runtime files
COPY calcom/package.json calcom/.yarnrc.yml calcom/turbo.json calcom/i18n.json ./
COPY calcom/.yarn ./.yarn
COPY --from=builder /calcom/yarn.lock ./yarn.lock
COPY --from=builder /calcom/node_modules ./node_modules
COPY --from=builder /calcom/packages ./packages
COPY --from=builder /calcom/apps/web ./apps/web
COPY --from=builder /calcom/packages/prisma/schema.prisma ./prisma/schema.prisma

# Bring in helper scripts
COPY scripts scripts

# Save build-time URL for start.sh patching
ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL

# Fix static URLs in the build output
RUN scripts/replace-placeholder.sh http://NEXT_PUBLIC_WEBAPP_URL_PLACEHOLDER ${NEXT_PUBLIC_WEBAPP_URL}

# Stage 3: runtime image
FROM node:18 AS runner

WORKDIR /calcom
COPY --from=builder-two /calcom ./

ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000
ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    NODE_ENV=production \
    PORT=3000

EXPOSE 3000

# Ensure shell scripts are LF and executable
RUN apt-get update \
    && apt-get install -y bash dos2unix \
    && find ./scripts -type f -name '*.sh' -print0 | xargs -0 dos2unix \
    && find ./scripts -type f -name '*.sh' -print0 | xargs -0 chmod +x

HEALTHCHECK --interval=30s --timeout=30s --retries=5 \
    CMD wget --spider http://localhost:3000 || exit 1

# Launch under bash so PORT is respected by Next.js
ENTRYPOINT ["bash", "/calcom/scripts/start.sh"]
