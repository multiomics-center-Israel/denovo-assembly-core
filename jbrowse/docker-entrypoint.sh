#!/bin/sh
# nginx:alpine runs /docker-entrypoint.d/*.sh before launching nginx.
# Generate basic-auth .htpasswd from env; password stays in Railway env vars,
# never in the repo/image. Falls back to the baked default if SITE_PASSWORD unset.
set -e

if [ -n "$SITE_PASSWORD" ]; then
  htpasswd -cbB /etc/nginx/.htpasswd "${SITE_USER:-spalangia}" "$SITE_PASSWORD"
  echo "[htpasswd] set for user '${SITE_USER:-spalangia}'"
else
  echo "[htpasswd] SITE_PASSWORD unset; using baked default"
fi
