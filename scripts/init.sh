#!/bin/bash
set -e

echo "=== diwansync init ==="
echo ""

# Create /storage directory structure
if [ ! -d /storage ]; then
    echo "Creating /storage directory..."
    sudo mkdir -p /storage
else
    echo "/storage already exists, skipping creation."
fi

# Copy template files
echo "Copying storage.template to /storage..."
sudo cp -r storage.template/* /storage/

# Generate secrets for services that need them
echo ""
echo "Generating secrets..."

# 004-authentik
if ! grep -q "^POSTGRES_PASSWORD=" /storage/env/004-authentik.env 2>/dev/null; then
    echo "POSTGRES_PASSWORD=$(openssl rand -base64 36)" | sudo tee -a /storage/env/004-authentik.env > /dev/null
    echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60)" | sudo tee -a /storage/env/004-authentik.env > /dev/null
    echo "  ✓ 004-authentik secrets generated"
else
    echo "  - 004-authentik secrets already exist, skipping"
fi

# 005-immich
if ! grep -q "^DB_PASSWORD=" /storage/env/005-immich.env 2>/dev/null; then
    echo "DB_PASSWORD=$(openssl rand -base64 36)" | sudo tee -a /storage/env/005-immich.env > /dev/null
    echo "  ✓ 005-immich secrets generated"
else
    echo "  - 005-immich secrets already exist, skipping"
fi

# Seed the Immich instance config from the local template (no compile needed for local-only).
# The template ships with oauth disabled by default; run
# services/005-immich/compile-remote-access.sh to overwrite it with remote SSO values.
if [ ! -f /storage/volumes/005-immich/instance-config.yml ]; then
    echo "Seeding 005-immich instance config..."
    sudo cp services/005-immich/config.yml /storage/volumes/005-immich/instance-config.yml
else
    echo "  - 005-immich instance config already exists, skipping"
fi

echo ""
echo "=== Init complete ==="
echo "Edit /storage/env/*.env files with your settings, then run: docker compose up -d"