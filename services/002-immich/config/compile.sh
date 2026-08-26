#!/bin/bash
# Compile Immich's monuted config from parameters and feature flags under 002-immich.env.
# Idempotent: rebuilds instance-config.yml = base [+ oauth] [+ smtp] from the current flags.
# Writes into /compiled/config.yml, ran inside the container.
set -euo pipefail

# Create the folder directly in container memory
mkdir -p /compiled

parse_template() {
    while IFS= read -r line || [ -n "$line" ]; do
        eval "echo \"${line//\"/\\\"}\""
    done
}

echo "Compiling base config..."
parse_template < /config/template.config.yml > /compiled/config.yml

if [ "${ENABLE_OAUTH:-false}" = "true" ]; then
    echo "Compiling OAuth configuration..."
    parse_template < /config/template.oauth.yml >> /compiled/config.yml
fi

if [ "${ENABLE_SMTP:-false}" = "true" ]; then
    echo "Compiling SMTP configuration..."
    parse_template < /config/template.smtp.yml >> /compiled/config.yml
fi

echo "Configuration successfully compiled at /compiled/config.yml!"