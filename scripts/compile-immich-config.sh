#!/bin/bash
# Compile Immich's persisted instance config from the feature flags in the immich env.
# Idempotent: rebuilds instance-config.yml = base [+ oauth] [+ smtp] from the current flags.
# Writes only into ./storage (untracked). Re-run after changing flags/values.
set -euo pipefail

ENV_FILE=./storage/env/002-immich.env
DIR=./services/002-immich
OUT=./storage/volumes/002-immich/instance-config.yml

set -a; source "$ENV_FILE"; set +a
mkdir -p "$(dirname "$OUT")"

# base (offline-valid: externalDomain substituted, oauth absent)
envsubst < "$DIR/config.yml" > "$OUT"

# optional feature blocks, appended only when their flag is on
if [ "${ENABLE_OAUTH:-false}" = true ]; then
    envsubst < "$DIR/config.oauth.snippet.yml" >> "$OUT"
fi
if [ "${ENABLE_SMTP:-false}" = true ]; then
    envsubst < "$DIR/config.smtp.snippet.yml" >> "$OUT"
fi
