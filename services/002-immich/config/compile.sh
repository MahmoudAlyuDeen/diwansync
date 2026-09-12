#!/bin/bash
# Compiles Immich configuration template with env variables:
# - config template: <repo>/services/002-immich/config/config.yml
# - env variables: <storage>/env/002-immich.env and <storage>/env/004-dyngress.env.
# - the config template and this compile script are bind mounted under ./config:/config
# - writes into /compiled/config.yml, runs inside the container.
# - the compiled configuration is ephemeral, it recompiles on every container start.
set -euo pipefail

# Create the folder directly in container memory
mkdir -p /compiled

parse_template() {
    while IFS= read -r line || [ -n "$line" ]; do
        eval "echo \"${line//\"/\\\"}\""
    done
}

echo "Compiling Immich configuration..."
parse_template < /config/config.yml > /compiled/config.yml

echo "Configuration successfully compiled at /compiled/config.yml!"
cat /compiled/config.yml