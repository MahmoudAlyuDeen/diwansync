#!/bin/bash
# Generate or rotate per-service secrets, then seed Immich's instance template.
# Existing secrets are shown and kept unless you choose to rotate.
# Safe to run standalone; run after setup.sh has wired ./storage.
set -e

cd "$(dirname "$0")/.."   # repo root

secrets=(
    "./storage/env/002-immich.env    DB_PASSWORD"
    "./storage/env/004-dyngress.env  AUTHELIA_SESSION_SECRET"
    "./storage/env/004-dyngress.env  AUTHELIA_STORAGE_ENCRYPTION_KEY"
    "./storage/env/004-dyngress.env  AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET"
)

[ -d ./storage/env ] || { echo "No ./storage/env — run ./setup.sh first."; exit 1; }

confirm() { local r; read -rp "$1 [y/n] " r; [[ "${r:-n}" == [Yy]* ]]; }
gen_hex() { openssl rand -hex 24; }

total=${#secrets[@]}; index=0
for entry in "${secrets[@]}"; do
    index=$((index + 1))
    read -r file name <<< "$entry"

    echo ""
    # Check if secret already exists in the target env file.
    line=$(grep -m1 "^${name}=" "$file" 2>/dev/null) || true
    if [ -n "${line:-}" ]; then
        echo "[${index}/${total}] A secret already exists:"
        echo "${file}"
        echo "${line}"
        if confirm "Backup and generate a new secret?"; then

            # Double-confirm before writing
            if confirm "Careful: Rotating might break existing deployments.
Existing secret will be retained so you can manually reverse this.
Are you sure?"; then
                echo "Rotating ${name} in ${file}..."
                sed -i '' "s/^${name}=/# ROTATED: ${name}=/" "$file"

                printf '\n%s=%s\n' "$name" "$(gen_hex)" >> "$file"
                echo "rotated (old value commented out)"

            else
                echo "Rotation cancelled. Keeping existing value."
            fi

        else
            echo "kept, no changes made"
        fi
    else
        printf '\n%s=%s\n' "$name" "$(gen_hex)" >> "$file"
        echo "[${index}/${total}] ${name} generated in ${file}"
    fi
done

echo ""
echo "✓ Secrets ready."
