#!/bin/bash
# Generate or rotate per-service secrets, then seed Immich's instance config.
# Existing secrets are shown and kept unless you choose to rotate.
# Safe to run standalone; run after setup.sh has wired ./storage.
set -e

cd "$(dirname "$0")/.."   # repo root

secrets=(
    "POSTGRES_PASSWORD    ./storage/env/005-authentik.env"
    "AUTHENTIK_SECRET_KEY ./storage/env/005-authentik.env"
    "DB_PASSWORD          ./storage/env/002-immich.env"
)

[ -d ./storage/env ] || { echo "No ./storage/env — run ./setup.sh first."; exit 1; }

confirm() { local r; read -rp "$1 [y/N] " r; [[ "${r:-N}" == [Yy]* ]]; }
gen_hex() { openssl rand -hex 24; }

# ensure_secret <name> <file> <idx> <total>
ensure_secret() {
    local name="$1" file="$2" idx="$3" total="$4" line
    echo ""
    if line="$(grep -m1 "^${name}=" "$file" 2>/dev/null)"; then
        echo "[${idx}/${total}] ${name} exists in ${file}"
        echo "    current: ${line#"${name}="}"
        if confirm "    rotate it? (breaks the existing deployment)"; then
            sed -i.bak "/^${name}=/d" "$file" && rm -f "${file}.bak"
            printf '%s=%s\n' "$name" "$(gen_hex)" >> "$file"
            echo "  ✓ rotated"
        else
            echo "  - kept"
        fi
    else
        printf '\n%s=%s\n' "$name" "$(gen_hex)" >> "$file"
        echo "[${idx}/${total}] ${name} generated in ${file} ✓"
    fi
}

total=${#secrets[@]}; idx=0
for entry in "${secrets[@]}"; do
    idx=$((idx + 1))
    read -r name file <<< "$entry"
    ensure_secret "$name" "$file" "$idx" "$total"
done

# Seed Immich's instance config from the base template (no compile).
cfg=./storage/volumes/002-immich/instance-config.yml
echo ""
if [ -f "$cfg" ]; then
    echo "  - 002-immich instance config already exists, skipping"
else
    echo "Seeding 002-immich instance config..."
    mkdir -p "$(dirname "$cfg")"
    cp ./services/002-immich/config.yml "$cfg"
fi

echo ""
echo "Secrets ready."