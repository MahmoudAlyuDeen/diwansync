#!/bin/bash
# Compile config.yml into a merged config, substituting secrets from the env file.
# Run this after editing config.yml or the env secrets, before starting the service.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../../storage/env/005-immich.env"
OUTPUT_DIR="${SCRIPT_DIR}/../../storage/volumes/005-immich"
OUTPUT_FILE="${OUTPUT_DIR}/merged-config.yml"

if [ ! -f "${ENV_FILE}" ]; then
    echo "Env file not found: ${ENV_FILE}" >&2
    echo "Run init.sh and edit storage/env/005-immich.env first." >&2
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"

set -a
source "${ENV_FILE}"
set +a

envsubst < "${SCRIPT_DIR}/config.yml" > "${OUTPUT_FILE}"

echo "Wrote merged config to ${OUTPUT_FILE}"