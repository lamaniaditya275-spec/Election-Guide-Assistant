# ---- Build Stage ----
FROM node:18-alpine AS builder
WORKDIR /app

# Copy dependency manifests first (better layer caching)
COPY package*.json ./

# Install all dependencies (including devDependencies needed for build)
RUN npm ci --legacy-peer-deps

# Copy source code
COPY . .

# Build production bundle
RUN npm run build

# ---- Serve Stage ----
FROM nginx:stable-alpine
WORKDIR /usr/share/nginx/html

# Remove default nginx static assets
RUN rm -rf ./*

# Copy build output from builder stage
COPY --from=builder /app/build .

# Custom nginx config to handle React Router (SPA) and port 8080 (required by Cloud Run)
RUN echo 'server { \
    listen 8080; \
    root /usr/share/nginx/html; \
    index index.html; \
    location / { \
        try_files $uri $uri/ /index.html; \
    } \
    # Cache static assets aggressively \
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ { \
        expires 1y; \
        add_header Cache-Control "public, immutable"; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
