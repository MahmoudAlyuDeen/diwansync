#!/bin/bash
# Compiles Immich configuration template with env variables:
# - config templates:
#   - <repo>/services/002-immich/config/config-base.yml
#   - <repo>/services/002-immich/config/config-oauth.yml
#   - <repo>/services/002-immich/config/config-smtp.yml
# - env variables: <storage>/env/002-immich.env.
# - config templates and this compile script are bind mounted under ./config:/config
# - writes into /compiled/configuration.yml, runs inside the container.
# - the compiled configuration is ephemeral, it recompiles on every container start.
set -euo pipefail

# Create the folder directly in container memory
mkdir -p /compiled

parse_template() {
    while IFS= read -r line || [ -n "$line" ]; do
        eval "echo \"${line//\"/\\\"}\""
    done
}

echo "Compiling base config..."
parse_template < /config/config-base.yml > /compiled/config.yml

if [ "${ENABLE_OAUTH:-false}" = "true" ]; then
    echo "Compiling OAuth configuration..."
    parse_template < /config/config-oauth.yml >> /compiled/config.yml
fi

if [ "${ENABLE_SMTP:-false}" = "true" ]; then
    echo "Compiling SMTP configuration..."
    parse_template < /config/config-smtp.yml >> /compiled/config.yml
fi

echo "Configuration successfully compiled at /compiled/config.yml!"