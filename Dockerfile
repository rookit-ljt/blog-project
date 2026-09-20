# Stage 1: Build static site
FROM node:22-alpine AS builder
WORKDIR /app

# Enable pnpm via corepack
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
ENV ASTRO_TELEMETRY_DISABLED=1
RUN corepack enable && corepack prepare pnpm@latest --activate

# Cache dependencies
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Copy source and build
COPY . .
RUN pnpm run build

# Stage 2: Serve with high-performance Nginx
FROM nginx:mainline-alpine-slim AS runner

# Replace default Nginx configuration
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

# Copy build output
COPY --from=builder /app/dist /usr/share/nginx/html

# Expose HTTP port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
