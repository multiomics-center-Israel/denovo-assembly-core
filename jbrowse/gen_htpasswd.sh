#!/usr/bin/env bash
# Regenerate jbrowse/.htpasswd with your shared password.
# Usage: SITE_USER=spalangia SITE_PASSWORD=yourpass bash gen_htpasswd.sh
set -euo pipefail
U="${SITE_USER:-spalangia}"; P="${SITE_PASSWORD:?set SITE_PASSWORD}"
printf '%s:%s\n' "$U" "$(openssl passwd -apr1 "$P")" > "$(dirname "$0")/.htpasswd"
echo "wrote $(dirname "$0")/.htpasswd for user '$U'"
