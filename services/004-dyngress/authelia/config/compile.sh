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

decode_rsa() { printf '%s' "$1" | base64 -d | sed 's/^/          /'; }

parse_template() {
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "${line#*AUTHELIA_OIDC_PRIVATE_KEY}" != "$line" ] && [ -n "${AUTHELIA_OIDC_PRIVATE_KEY:-}" ]; then
            decode_rsa "${AUTHELIA_OIDC_PRIVATE_KEY}"
        else
            escaped=$(printf '%s' "$line" | sed 's/"/\\"/g')
            eval "echo \"$escaped\""
        fi
    done
}

parse_template < /config/configuration.yml > /compiled/configuration.yml
echo "Configuration successfully compiled at /compiled/configuration.yml!"
cat /compiled/configuration.yml