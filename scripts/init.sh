#!/bin/bash
set -e

echo "=== diwansync init ==="
echo ""

if [ ! -d ./storage ]; then
    echo "Creating ./storage directory..."
    mkdir -p ./storage
else
    echo "./storage already exists, skipping creation."
fi

echo "Seeding storage.template into ./storage (existing files preserved)..."
# Seed only missing files; never overwrite existing secrets/config.
# cp -Rn exits non-zero when it skips existing files, which is expected here.
cp -Rn ./storage.template/* ./storage/ || true

echo ""
echo "Generating secrets..."

if ! grep -q "^POSTGRES_PASSWORD=" ./storage/env/005-authentik.env 2>/dev/null; then
    printf "\nPOSTGRES_PASSWORD=%s\n" "$(openssl rand -base64 36 | tr -d '\n')" >> ./storage/env/005-authentik.env
    printf "AUTHENTIK_SECRET_KEY=%s\n" "$(openssl rand -base64 60 | tr -d '\n')" >> ./storage/env/005-authentik.env
    echo "  ✓ 005-authentik secrets generated"
else
    echo "  - 005-authentik secrets already exist, skipping"
fi

if ! grep -q "^DB_PASSWORD=" ./storage/env/002-immich.env 2>/dev/null; then
    printf "\nDB_PASSWORD=%s\n" "$(openssl rand -base64 36 | tr -d '\n')" >> ./storage/env/002-immich.env
    echo "  ✓ 002-immich secrets generated"
else
    echo "  - 002-immich secrets already exist, skipping"
fi

if [ ! -f ./storage/volumes/002-immich/instance-config.yml ]; then
    echo "Seeding 002-immich instance config..."
    mkdir -p ./storage/volumes/002-immich
    cp ./services/002-immich/config.yml ./storage/volumes/002-immich/instance-config.yml
else
    echo "  - 002-immich instance config already exists, skipping"
fi

echo ""
echo "=== Init complete ==="
echo "Edit ./storage/env/*.env files with your settings, then run: docker compose up -d"