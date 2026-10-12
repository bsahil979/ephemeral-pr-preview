# ==========================================================
# Stage 1: Production Dependencies Builder
# ==========================================================
FROM node:22-alpine AS builder

WORKDIR /usr/src/app

# Copy dependency manifests
COPY package*.json ./

# Install only production dependencies
RUN npm ci --omit=dev --ignore-scripts

# ==========================================================
# Stage 2: Final Minimal Production Image
# ==========================================================
FROM node:22-alpine AS runner

WORKDIR /usr/src/app

# Set production environment defaults
ENV NODE_ENV=production \
    PORT=3000

# Copy installed production dependencies from builder stage
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY package*.json ./
COPY src/ ./src/

# Use built-in unprivileged node user for least privilege security
USER node

# Expose default application port
EXPOSE 3000

# Health check using Node 22 built-in fetch (zero curl/wget dependencies needed)
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://localhost:' + (process.env.PORT || 3000) + (process.env.BASE_PATH || '') + '/health').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"

# Start the application
CMD ["node", "src/server.js"]
