# ============================================================
# Multi-stage Dockerfile — Security hardened
# Stage 1: Install dependencies (build stage)
# Stage 2: Production image (minimal attack surface)
# ============================================================

# ── Stage 1: Builder ─────────────────────────────────────────
# Use a specific digest/tag — never use 'latest' in production
# because it can silently change and introduce vulnerabilities
FROM node:18.20.4-alpine3.20 AS builder

WORKDIR /app

# Copy only package files first — Docker layer caching
# means npm install only re-runs when package files change
COPY package*.json ./

# ci = clean install (faster, reproducible, uses package-lock.json)
# --only=production = skip devDependencies (smaller image, smaller attack surface)
RUN npm ci --only=production && \
    npm cache clean --force

# ── Stage 2: Production ──────────────────────────────────────
FROM node:18.20.4-alpine3.20

# Security: update base packages to get latest security patches
RUN apk update && \
    apk upgrade --no-cache && \
    # Remove package manager cache
    rm -rf /var/cache/apk/*

WORKDIR /app

# Security: create a non-root user to run the app
# Running as root is a critical security vulnerability
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Copy only production node_modules from builder stage
# This excludes devDependencies, test files, and build artifacts
COPY --from=builder --chown=appuser:appgroup /app/node_modules ./node_modules

# Copy application source
COPY --chown=appuser:appgroup app/src ./src
COPY --chown=appuser:appgroup app/package.json ./

# Security: switch to non-root user before running
USER appuser

# Document which port the app uses (doesn't actually publish it)
EXPOSE 3000

# Health check — Docker and Kubernetes use this to know if the container is healthy
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Use exec form (not shell form) — prevents shell injection,
# proper signal handling (SIGTERM reaches the Node process)
CMD ["node", "src/index.js"]
