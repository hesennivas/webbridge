# syntax=docker/dockerfile:1
# static landing site: build with vite, serve the /dist bundle with caddy.

# --- 1. build the static bundle ---
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build
# vite outputs to /app/dist

# --- 2. minimal static runtime (caddy: gzip/zstd, spa fallback, tiny image) ---
FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /app/dist /srv
# railway injects $PORT; caddy binds it (see Caddyfile). no EXPOSE needed.
