# Stage 1: Build static site
FROM node:22-slim AS builder
WORKDIR /app

# Set environment variables
ENV ASTRO_TELEMETRY_DISABLED=1
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Install pinned pnpm version matching local development
RUN npm install -g pnpm@10.26.0

# Copy package definitions, lockfile, AND workspace config (essential for pnpm allowBuilds / sharp / esbuild)
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml* ./

# Configure high-speed npm mirror and install dependencies
RUN pnpm config set registry https://registry.npmmirror.com && \
    pnpm install

# Copy project source and build static output
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
