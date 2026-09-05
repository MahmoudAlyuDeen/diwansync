#!/bin/sh
# Compiles Authelia configuration template with env variables:
# - config template: <repo>/services/004-dyngress/authelia/config/configuration.yml
# - env variables: <storage>/env/004-dyngress.env.
# - the config template and this compile script are bind mounted under ./config:/config
# - writes into /compiled/configuration.yml, runs inside the container.
# - the compiled configuration is ephemeral, it recompiles on every container start.
set -eu

# Create the folder directly in container memory
mkdir -p /compiled

parse_template() {
    while IFS= read -r line || [ -n "$line" ]; do
        escaped=$(printf '%s' "$line" | sed 's/"/\\"/g')
        eval "echo \"$escaped\""
    done
}

parse_template < /config/configuration.yml > /compiled/configuration.yml
echo "Configuration successfully compiled at /compiled/configuration.yml!"
