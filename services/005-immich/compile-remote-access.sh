#!/bin/bash
set -a
source .env
set +a
envsubst < config.yml > ../../storage/volumes/005-immich/instance-config.yml
echo "Wrote instance config to ../../storage/volumes/005-immich/instance-config.yml"
