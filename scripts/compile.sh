#!/bin/sh
# Compiles configuration template with environment variables.
# - config template is bind-mounted as /config/configuration.yml
# - this compile script is bind-mounted as /config/compile.sh
# - writes into /compiled/configuration.yml, runs inside the container.
# - the compiled configuration is ephemeral, it recompiles on every container start.
set -eu

# Create the folder directly in container memory
mkdir -p /compiled

decode_rsa() { printf '%s' "$1" | base64 -d | sed 's/^/          /'; }

parse_template() {
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "${AUTHELIA_OIDC_PRIVATE_KEY:-}" ] && \
           [ "${line#*AUTHELIA_OIDC_PRIVATE_KEY}" != "$line" ]; then
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