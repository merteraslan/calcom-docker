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

# Copy only manifest and lock for turbo
COPY calcom/package.json calcom/yarn.lock calcom/turbo.json ./
COPY calcom/.yarn ./.yarn

# Copy source
COPY calcom/apps/web ./apps/web
COPY calcom/apps/api/v2 ./apps/api/v2
COPY calcom/packages ./packages
COPY calcom/tests ./tests

RUN yarn install --immutable --immutable-cache --check-cache
RUN npx turbo run build --filter=@calcom/web --filter=@calcom/trpc

# Stage 2: assemble production files
FROM node:18 AS builder-two

WORKDIR /calcom
ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000
ENV NODE_ENV=production

# Bring in only runtime artifacts
COPY calcom/package.json calcom/.yarnrc.yml calcom/turbo.json ./
COPY calcom/.yarn ./.yarn
COPY --from=builder /calcom/yarn.lock ./yarn.lock
COPY --from=builder /calcom/node_modules ./node_modules
COPY --from=builder /calcom/packages ./packages

# Copy built web app
COPY --from=builder /calcom/apps/web/.next ./apps/web/.next
COPY --from=builder /calcom/apps/web/public ./apps/web/public
COPY --from=builder /calcom/apps/web/package.json ./apps/web/package.json

# Bring in helper scripts
COPY scripts scripts

# Preserve the build-time URL for start.sh
ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL

# Fix any static URLs
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

# Ensure bash + normalize scripts
RUN apt-get update && apt-get install -y bash dos2unix \
    && find ./scripts -type f -name '*.sh' -print0 | xargs -0 dos2unix \
    && find ./scripts -type f -name '*.sh' -print0 | xargs -0 chmod +x

HEALTHCHECK --interval=30s --timeout=30s --retries=5 \
    CMD wget --spider http://localhost:3000 || exit 1

ENTRYPOINT ["bash","/calcom/scripts/start.sh"]