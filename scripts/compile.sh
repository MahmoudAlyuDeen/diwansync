#!/bin/sh
# Compiles configuration template with environment variables.
# - config template is bind-mounted as /config/configuration.yml
# - this compile script is bind-mounted as /config/compile.sh
# - writes into /compiled/configuration.yml, runs inside the container.
# - the compiled configuration is ephemeral, it recompiles on every container start.
# - bare images only (no bash/envsubst/perl): substitution stays eval-based, POSIX sh + coreutils/sed/grep/base64.
# - client_secret: (Authelia) and clientSecret: (Immich) are the OAuth client secret keys of both templates.
# - Authelia's is compiled as a PBKDF2 digest because its file backend stores digests; Immich's passes through raw because it authenticates to Authelia with it.
set -eu

# Create the folder directly in container memory
mkdir -p /compiled

decode_rsa() { printf '%s' "$1" | base64 -d | sed 's/^/          /'; }

hash_client_secret() {
    if [ -n "${AUTHELIA_IMMICH_OAUTH_CLIENT_SECRET:-}" ]; then
        authelia crypto hash generate pbkdf2 --password "$AUTHELIA_IMMICH_OAUTH_CLIENT_SECRET" 2>/dev/null | sed -n 's/^Digest: //p'
    fi
}

parse_template() {
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "${AUTHELIA_OIDC_PRIVATE_KEY:-}" ] && \
           echo "$line" | grep -q "AUTHELIA_OIDC_PRIVATE_KEY"; then
            decode_rsa "${AUTHELIA_OIDC_PRIVATE_KEY}"
        elif echo "$line" | grep -q "client_secret:"; then
            printf '        client_secret: '\''%s'\''\n' "$(hash_client_secret)"
        else
            escaped=$(printf '%s' "$line" | sed 's/"/\\"/g')
            eval "echo \"$escaped\""
        fi
    done
}

parse_template < /config/configuration.yml > /compiled/configuration.yml
echo "Configuration successfully compiled at /compiled/configuration.yml!"