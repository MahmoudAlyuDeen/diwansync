#!/bin/bash
# Generate or rotate per-service secrets, then seed Immich's instance template.
# Existing secrets are shown and kept unless you choose to rotate.
# Safe to run standalone; run after setup.sh has wired ./storage.
set -e

cd "$(dirname "$0")/.."   # repo root

secrets=(
    "hex  ./storage/env/002-immich.env    DB_PASSWORD"
    "hex  ./storage/env/004-dyngress.env  AUTHELIA_SESSION_SECRET"
    "hex  ./storage/env/004-dyngress.env  AUTHELIA_STORAGE_ENCRYPTION_KEY"
    "hex  ./storage/env/004-dyngress.env  AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET"
    "hex  ./storage/env/004-dyngress.env  AUTHELIA_IMMICH_OAUTH_CLIENT_SECRET"
    "hex  ./storage/env/004-dyngress.env  AUTHELIA_OIDC_HMAC_SECRET"
    "rsa  ./storage/env/004-dyngress.env  AUTHELIA_OIDC_PRIVATE_KEY"
    "mtls ./storage/env/004-dyngress.env  CADDY_MTLS_CA_PRIVATE_KEY"
)

[ -d ./storage/env ] || { echo "No ./storage/env — run ./setup.sh first."; exit 1; }
[ -d ./storage/keys ] || { echo "No ./storage/keys — run ./setup.sh first."; exit 1; }

confirm() { local r; read -rp "$1 [y/n] " r; [[ "${r:-n}" == [Yy]* ]]; }
gen_hex() { openssl rand -hex 24; }
gen_rsa() { printf '%s' "$(openssl genrsa 2048 2>/dev/null)" | base64 -w0; }

# --- prompt_rotation (returns: 0=rotate, 1=keep) ------------------------------
prompt_rotation() {
    local line="$1" index="$2" total="$3" msg_extra="${4:-}"
    local msg_rotate="Backup and rotate? Existing secret will be retained so you can manually reverse this."

    echo "[${index}/${total}] A secret already exists:"
    if [ ${#line} -gt 80 ]; then
        printf '%s...\n' "${line:0:80}"
    else
        echo "$line"
    fi
    if ! confirm "$msg_rotate"; then
        echo "Kept, no changes made."; return 1
    fi
    if ! confirm "Careful: Rotating might break existing deployments. $msg_extra"; then
        echo "Rotation cancelled. Keeping existing value."; return 1
    fi
    return 0   # user agreed to rotate
}

# --- Type handlers ------------------------------------------------------------
handle_hex() {
    local file="$1" name="$2" index="$3" total="$4"
    local line=$(grep -m1 "^${name}=" "$file" 2>/dev/null || true)

    echo "" >&2
    if [ -z "${line:-}" ]; then
        # new — no existing secret
        printf '\n%s=%s\n' "$name" "$(gen_hex)" >> "$file"
        echo "[${index}/${total}] ${name} generated in ${file}" >&2
    elif prompt_rotation "$line" "$index" "$total"; then
        # rotate — user confirmed
        sed -i '' "s/^${name}=/# ROTATED: ${name}=/" "$file"
        printf '\n%s=%s\n' "$name" "$(gen_hex)" >> "$file"
        echo "rotated (old value commented out)" >&2
    fi   # keep — nothing to do
}

# --- handle_rsa (returns: generated or current value) -------------------------
handle_rsa() {
    local file="$1" name="$2" index="$3" total="$4" msg_extra="${5:-}"
    local line=$(grep -m1 "^${name}=" "$file" 2>/dev/null || true)
    local val=""

    echo "" >&2
    if [ -z "${line:-}" ]; then
        # new — no existing secret
        val=$(gen_rsa)
        printf '\n%s=%s\n' "$name" "$val" >> "$file"
        echo "[${index}/${total}] ${name} generated in ${file}" >&2
    elif prompt_rotation "$line" "$index" "$total" "$msg_extra"; then
        # rotate — user confirmed
        val=$(gen_rsa)
        sed -i '' "s/^${name}=/# ROTATED: ${name}=/" "$file"
        printf '\n%s=%s\n' "$name" "$val" >> "$file"
        echo "rotated (old value commented out)" >&2
    fi   # keep — nothing to do
}

handle_mtls() {
    local file="$1" name="$2" index="$3" total="$4"
    local p12_path="./storage/keys/002-immich-mobile.p12"
    local ca_crt_path="./storage/keys/002-immich-server.crt"
    local ca_key="/tmp/_mtls_ca.key"
    local key_pem="/tmp/_mtls_client.key"
    local cert_pem="/tmp/_mtls_client.crt"
    local serial="/tmp/_mtls_ca.srl"

    # Delegate to handle_rsa for new/rotate logic
    handle_rsa "$file" "$name" "$index" "$total" "This will invalidate all existing mobile certificates."

    local key_val
    key_val=$(grep "^${name}=" "$file" | sed "s/^${name}=//")

    # --- Idempotency: compare current CA public key against existing 002-immich-server.crt ---
    local current_pub=$(printf '%s' "$key_val" | base64 -d | openssl rsa -pubout 2>/dev/null || true)
    if [ -f "$ca_crt_path" ]; then
        local existing_pub=$(openssl x509 -in "$ca_crt_path" -noout -pubkey 2>/dev/null || true)
        if [ "$current_pub" = "$existing_pub" ]; then
            echo "[${index}/${total}] ${p12_path} up to date — skip"; return
        fi
    fi

    # Decode CA private key from env var value
    printf '%s' "$key_val" | base64 -d > "$ca_key"

    # Write 002-immich-server.crt to storage (used for Caddy trust_pool + p12 bundle)
    openssl req -new -x509 -nodes -days 3650 -sha256 \
        -subj "/CN=DiwanSync Root CA" -key "$ca_key" \
        -out "$ca_crt_path"

    # Generate client key + sign (LibreSSL-compatible pipe)
    openssl genrsa 2048 2>/dev/null > "$key_pem"
    openssl req -new -key "$key_pem" \
        -subj "/CN=immich-mobile" | openssl x509 -req \
        -CA "$ca_crt_path" -CAkey "$ca_key" \
        -CAcreateserial -out "$cert_pem" -days 365

    # Package PKCS#12 with client cert + CA cert in the bundle (no password)
    openssl pkcs12 -export -in "$cert_pem" \
        -inkey "$key_pem" -certfile "$ca_crt_path" \
        -out "$p12_path" -passout pass:

    rm -f "$ca_key" "$serial" "$key_pem" "$cert_pem"
    echo "[${index}/${total}] ${p12_path} generated from CADDY_MTLS_CA_PRIVATE_KEY"
}

# --- Main loop ----------------------------------------------------------------
total=${#secrets[@]}; index=0
for entry in "${secrets[@]}"; do
    index=$((index + 1))
    read -r type file name <<< "$entry"

    case "$type" in
        hex) handle_hex "$file" "$name" "$index" "$total" ;;
        rsa) handle_rsa "$file" "$name" "$index" "$total" ;;
        mtls) handle_mtls "$file" "$name" "$index" "$total" ;;
    esac
done

echo ""
echo "✓ Secrets ready."
