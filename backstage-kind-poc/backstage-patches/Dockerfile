# ============================================================================
# Stage 1: Build the backend
# ============================================================================
FROM node:22-bookworm-slim AS build

RUN apt-get update && apt-get install -y \
    python3 g++ make git curl \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable

WORKDIR /app

COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn/releases/ .yarn/releases/
COPY packages/backend/package.json ./packages/backend/
COPY packages/app/package.json ./packages/app/

RUN yarn install --frozen-lockfile

COPY . .

# Skip yarn tsc (type-check only) — actual compilation is in the build steps below
RUN yarn --cwd packages/backend build
RUN yarn --cwd packages/app build

# ============================================================================
# Stage 2: Minimal production runtime
# ============================================================================
FROM node:22-bookworm-slim AS runtime

RUN apt-get update && apt-get install -y \
    libsqlite3-dev python3 g++ make curl \
    && rm -rf /var/lib/apt/lists/*

RUN addgroup --system --gid 1001 nodejs \
    && adduser --system --uid 1001 --ingroup nodejs backstage

WORKDIR /app

# Copy node_modules from build stage (avoids re-running yarn install)
COPY --from=build --chown=backstage:nodejs /app/node_modules ./node_modules
COPY --from=build --chown=backstage:nodejs /app/packages/backend/node_modules ./packages/backend/node_modules
COPY --from=build --chown=backstage:nodejs /app/package.json ./
COPY --from=build --chown=backstage:nodejs /app/packages/backend/package.json ./packages/backend/

# Copy the bundle tarball and extract it at workspace root /app
# bundle.tar.gz contains paths like: packages/backend/dist/index.cjs.js
COPY --from=build /app/packages/backend/dist/bundle.tar.gz ./
RUN tar xzf bundle.tar.gz && rm bundle.tar.gz \
    && chown backstage:nodejs /app \
    && chown -R backstage:nodejs /app/packages \
    && chmod 755 /app

# Copy the frontend build into the backend static dir
COPY --from=build --chown=backstage:nodejs /app/packages/app/dist ./packages/backend/dist/static

# Copy app config and catalog
COPY --chown=backstage:nodejs app-config.yaml app-config.local.yaml ./
COPY --chown=backstage:nodejs catalog/ /app/catalog/

USER backstage

EXPOSE 7007

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:7007/healthcheck || exit 1

ENV NODE_ENV=production \
    LOG_LEVEL=info

CMD ["node", "packages/backend/dist/index.cjs.js"]
