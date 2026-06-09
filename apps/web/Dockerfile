# =============================================================================
# Stage 1: Install production dependencies
# =============================================================================
FROM node:20-alpine3.20 AS deps

WORKDIR /app

# Use npm ci for deterministic, reproducible installs
COPY package.json package-lock.json* ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev --ignore-scripts

# =============================================================================
# Stage 2: Build (if needed — currently a plain JS app, no build step)
# =============================================================================
FROM node:20-alpine3.20 AS build

WORKDIR /app

# Copy only what's needed for the runtime
COPY --from=deps --link /app/node_modules ./node_modules
COPY --link server.js ./server.js
COPY --link public/ ./public/

# =============================================================================
# Stage 3: Runtime (distroless node)
# =============================================================================
FROM gcr.io/distroless/nodejs20-debian12:nonroot AS runtime

# OCI annotations
LABEL org.opencontainers.image.title="KMS Web"
LABEL org.opencontainers.image.description="Knowledge Management System — web frontend"
LABEL org.opencontainers.image.source="https://github.com/your-org/your-repo"
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /app

# Copy only the runtime artifacts from the build stage
COPY --from=build --link /app /app

ENV PORT=3000
EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["node", "-e", "require('http').get('http://localhost:3000/api/health', r => {process.exit(r.statusCode===200?0:1)}).on('error',()=>process.exit(1))"]

USER nonroot

ENTRYPOINT ["node"]
CMD ["server.js"]
