# Code Buddy 2 — Railway production image
# Multi-stage build; API + WebSocket server.

FROM node:20-bookworm AS builder

WORKDIR /app

# Native modules used by Code Buddy require a compiler toolchain at build time.
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
RUN npm ci

COPY . .

# companion-core is a workspace package. Its package metadata points to dist/,
# so build it before the root TypeScript compiler resolves the workspace import.
RUN npm run build --workspace=@phuetz/companion-core
RUN npm run build
RUN npm prune --omit=dev

FROM node:20-bookworm-slim AS production

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ripgrep curl ca-certificates gosu \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash --uid 1001 codebuddy

COPY --from=builder --chown=codebuddy:codebuddy /app/dist ./dist
COPY --from=builder --chown=codebuddy:codebuddy /app/node_modules ./node_modules
COPY --from=builder --chown=codebuddy:codebuddy /app/package.json ./package.json

# Keep the built workspace package available for the optional dynamic import.
COPY --from=builder --chown=codebuddy:codebuddy /app/packages/companion-core/package.json ./packages/companion-core/package.json
COPY --from=builder --chown=codebuddy:codebuddy /app/packages/companion-core/dist ./packages/companion-core/dist

COPY docker/railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod 0755 /usr/local/bin/railway-entrypoint.sh

# Railway should mount its single persistent volume at /workspace.
# HOME is deliberately moved into that volume so projects, sessions,
# SQLite/config, credentials and memory survive redeploys.
RUN mkdir -p /workspace \
    && chown -R codebuddy:codebuddy /workspace

ENV NODE_ENV=production \
    HOME=/workspace \
    CODEBUDDY_HOME=/workspace/.codebuddy

WORKDIR /workspace

EXPOSE 3000

# The entrypoint fixes volume ownership and then drops to the unprivileged
# application user. Railway's startCommand supplies the actual PORT.
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]

# Local Docker fallback.
CMD ["node", "/app/dist/index.js", "server", "--port", "3000", "--host", "0.0.0.0"]

# Railway performs the healthcheck itself via railway.json.
# No Docker HEALTHCHECK is defined because Railway injects a dynamic PORT.
