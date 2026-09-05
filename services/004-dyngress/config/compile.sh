#!/bin/sh
# Compile Authelia's mounted config from parameters and feature flags under <storage>/env/004-dyngress.env.
# Idempotent: rebuilds configuration.yml = base from the current flags.
# Writes into /compiled/configuration.yml, runs inside the container .
set -euo pipefail

# Create the folder directly in container memory
mkdir -p /compiled

parse_template() {
    while IFS= read -r line || [ -n "$line" ]; do
        escaped=$(printf '%s' "$line" | sed 's/"/\\"/g')
        eval "echo \"$escaped\""
    done
}

echo "Compiling base config..."
parse_template < /config/configuration.yml > /compiled/configuration.yml
echo "Configuration successfully compiled at /compiled/configuration.yml!"
