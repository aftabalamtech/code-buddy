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
RUN npm run build
RUN npm prune --omit=dev

FROM node:20-bookworm-slim AS production

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ripgrep curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash --uid 1001 codebuddy

COPY --from=builder --chown=codebuddy:codebuddy /app/dist ./dist
COPY --from=builder --chown=codebuddy:codebuddy /app/node_modules ./node_modules
COPY --from=builder --chown=codebuddy:codebuddy /app/package.json ./package.json

# Railway should mount its single persistent volume at /workspace.
# HOME is deliberately moved into that volume so projects, sessions,
# SQLite/config, credentials and memory survive redeploys.
RUN mkdir -p /workspace \
    && chown -R codebuddy:codebuddy /workspace

ENV NODE_ENV=production \
    HOME=/workspace \
    CODEBUDDY_HOME=/workspace/.codebuddy

USER codebuddy
WORKDIR /workspace

EXPOSE 3000

# Local Docker fallback. Railway overrides this with railway.json and uses
# Railway's injected PORT value.
CMD ["node", "/app/dist/index.js", "server", "--port", "3000", "--host", "0.0.0.0"]

# Docker-level health check; Railway separately checks /api/health on PORT.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD-SHELL curl -fsS "http://127.0.0.1:${PORT:-3000}/api/health" || exit 1
