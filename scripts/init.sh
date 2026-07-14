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

echo "Copying storage.template to ./storage..."
cp -r ./storage.template/* ./storage/

echo ""
echo "Generating secrets..."

if ! grep -q "^POSTGRES_PASSWORD=" ./storage/env/004-authentik.env 2>/dev/null; then
    printf "\nPOSTGRES_PASSWORD=%s\n" "$(openssl rand -base64 36)" >> ./storage/env/004-authentik.env
    printf "AUTHENTIK_SECRET_KEY=%s\n" "$(openssl rand -base64 60)" >> ./storage/env/004-authentik.env
    echo "  ✓ 004-authentik secrets generated"
else
    echo "  - 004-authentik secrets already exist, skipping"
fi

if ! grep -q "^DB_PASSWORD=" ./storage/env/005-immich.env 2>/dev/null; then
    printf "\nDB_PASSWORD=%s\n" "$(openssl rand -base64 36)" >> ./storage/env/005-immich.env
    echo "  ✓ 005-immich secrets generated"
else
    echo "  - 005-immich secrets already exist, skipping"
fi

if [ ! -f ./storage/volumes/005-immich/instance-config.yml ]; then
    echo "Seeding 005-immich instance config..."
    mkdir -p ./storage/volumes/005-immich
    cp ./services/005-immich/config.yml ./storage/volumes/005-immich/instance-config.yml
else
    echo "  - 005-immich instance config already exists, skipping"
fi

echo ""
echo "=== Init complete ==="
echo "Edit ./storage/env/*.env files with your settings, then run: docker compose up -d"