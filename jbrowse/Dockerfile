# Build the JBrowse 2 static site and serve it behind basic auth.
# config.json is generated locally by scripts/build_jbrowse_config_web.py (public
# Supabase + agent URLs only) and copied in — no host paths baked in.
FROM node:20-bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /site
RUN npx --yes @jbrowse/cli@latest create .
COPY config.json /site/config.json

FROM nginx:alpine
COPY --from=build /site /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY .htpasswd /etc/nginx/.htpasswd
EXPOSE 8080
