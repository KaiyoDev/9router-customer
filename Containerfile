# ⚠ DEPRECATED — Use production/Containerfile instead
# This file is kept for reference only.
# ARM64 production build uses: production/Containerfile
#
# syntax=docker/dockerfile:1.7
# ============================================================
# 9Router Production Container — ARM64 (aarch64) optimized
# Target: Low-RAM TV Box (~2GB), Podman rootless
# Base: node:22-alpine ( slim, ARM64 supported)
# ============================================================

# ── Stage 1: Builder ────────────────────────────────────────
FROM node:22-alpine AS builder

WORKDIR /build

# Install build tools needed for native deps (better-sqlite3 optional)
# and python3 for node-gyp. Alpine packages are small.
RUN apk --no-cache add \
      python3 \
      make \
      g++ \
    && rm -rf /var/cache/apk/*

# Copy only package manifests first (leverages Docker layer cache)
COPY package.json package-lock.json ./
COPY open-sse/package.json ./open-sse/ 2>/dev/null || true

# Install production deps only (no devDeps, no tests)
RUN npm ci --only=production --ignore-scripts \
    && rm -rf /root/.npm /tmp/* /var/tmp/*

# Copy source (exclude node_modules, .git, tests)
COPY --exclude=node_modules --exclude=.git --exclude=tests --exclude=cli \
     . .

# Disable Next.js telemetry & enable standalone output
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

# Build Next.js standalone output
RUN npm run build

# ── Stage 2: Runner (minimal runtime image) ─────────────────
FROM node:22-alpine AS runner

WORKDIR /app

# ── Security: run as non-root node user (uid 1000) ─────────
RUN addgroup -g 1000 -S nodejs \
    && adduser -u 1000 -S nodejs -G nodejs -h /app

# ── Runtime environment ────────────────────────────────────
ENV NODE_ENV=production \
    PORT=20128 \
    HOSTNAME=0.0.0.0 \
    NEXT_TELEMETRY_DISABLED=1 \
    # Data persistence path (SQLite DB)
    DATA_DIR=/app/data \
    # Disable request logging to save disk I/O
    ENABLE_REQUEST_LOGS=false \
    # Disable observability/cloud sync if not needed
    OBSERVABILITY_ENABLED=false \
    # Node.js memory limits for ~2GB RAM host
    # Heap ceiling 512MB leaves ~1.4GB for OS + container overhead
    NODE_OPTIONS="--max-old-space-size=512 --no-warnings"

# ── Copy standalone output from builder ────────────────────
# Standalone layout: /app/server.js, /app/.next/, /app/node_modules/
COPY --from=builder /build/.next/standalone/ ./

# ── Copy standalone-missing deps that Next tracing omits ──
# These are in serverExternalPackages and won't be auto-copied.
COPY --from=builder /build/node_modules/better-sqlite3 ./node_modules/better-sqlite3
COPY --from=builder /build/node_modules/sql.js     ./node_modules/sql.js
COPY --from=builder /build/node_modules/open      ./node_modules/open
# next itself may be omitted by tracing
COPY --from=builder /build/node_modules/next      ./node_modules/next

# ── Copy custom server wrapper (IP sanitization) ──────────
COPY --from=builder /build/custom-server.js ./custom-server.js

# ── Copy public assets & static files ──────────────────────
COPY --from=builder /build/public   ./public
COPY --from=builder /build/.next/static ./.next/static

# ── Copy MITM source (needed at runtime for proxy mode) ───
COPY --from=builder /build/src/mitm ./src/mitm

# ── Create data dirs & set permissions ─────────────────────
RUN mkdir -p /app/data /app/logs \
    && chown -R nodejs:nodejs /app \
    && chmod -R 755 /app

# ── Switch to non-root user ────────────────────────────────
USER nodejs

# ── Healthcheck: lightweight HTTP ping ─────────────────────
# Uses /api/auth/status — returns 200 JSON when app is up.
# Interval 30s, timeout 5s, retries 3, start period 20s (slow ARM boot).
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=20s \
  CMD node -e "const http=require('http');const opts={hostname:'127.0.0.1',port:20128,path:'/api/auth/status',timeout:5000};const req=http.request(opts,res=>{process.exit(res.statusCode===200?0:1)});req.on('error',()=>process.exit(1));req.end();"

# ── Expose only the API port ───────────────────────────────
EXPOSE 20128

# ── Graceful shutdown entrypoint ───────────────────────────
# Traps SIGTERM/SIGINT, shuts down HTTP server then exits.
# Node.js alpine image ships a proper kill signal handler already,
# but we add an explicit wrapper for clarity.
cat > /app/entrypoint.sh << 'ENTRYPOINT'
#!/bin/sh
set -e

# Ensure data dir exists and is writable
mkdir -p /app/data /app/logs

# Start the Next.js standalone server via custom wrapper
exec node custom-server.js
ENTRYPOINT
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
CMD []
