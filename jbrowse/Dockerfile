# Build the JBrowse 2 static site and serve it behind basic auth.
# config.json holds public URLs only (Supabase + agent) — no host paths baked in.
# The .htpasswd is generated at startup from SITE_USER/SITE_PASSWORD env vars
# (docker-entrypoint.sh); the baked .htpasswd is only a fallback default.
FROM node:20-bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /site
RUN npx --yes @jbrowse/cli@latest create .
COPY config.json /site/config.json

FROM nginx:alpine
RUN apk add --no-cache apache2-utils
COPY --from=build /site /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY .htpasswd /etc/nginx/.htpasswd
COPY docker-entrypoint.sh /docker-entrypoint.d/99-htpasswd.sh
RUN chmod +x /docker-entrypoint.d/99-htpasswd.sh
EXPOSE 8080
