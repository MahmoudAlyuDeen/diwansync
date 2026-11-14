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
        perl -pi -e "s/^${name}=/# ROTATED: ${name}=/" "$file"
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
        perl -pi -e "s/^${name}=/# ROTATED: ${name}=/" "$file"
        printf '\n%s=%s\n' "$name" "$val" >> "$file"
        echo "rotated (old value commented out)" >&2
    fi   # keep — nothing to do
}

handle_mtls() {
    local file="$1" name="$2" index="$3" total="$4"
    local p12_path="./storage/keys/002-immich-mobile.p12"
    local ca_crt_path="./storage/keys/002-immich-server.crt"
    local p12_password="immich"

    # Capture the CA key as it stands before this run, so the replaced pair can be named after its key.
    local old_ca_key=$(grep -m1 "^${name}=" "$file" 2>/dev/null | sed "s/^${name}=//")

    # Delegate to handle_rsa for new/rotate logic
    handle_rsa "$file" "$name" "$index" "$total" "This invalidates existing mobile certificates; old certs will be retained."

    if [ -d "$ca_crt_path" ]; then
        echo "Removing stray directory at $ca_crt_path, happens if docker runs prior to generation"
        rm -rf "$ca_crt_path"
    fi

    local key_val=$(grep -m1 "^${name}=" "$file" | sed "s/^${name}=//")

    # missing or incomplete pair.
    if [ ! -f "$ca_crt_path" ] || [ ! -f "$p12_path" ]; then
        gen_mtls_pair "$key_val" "$ca_crt_path" "$p12_path" "$p12_password"
        echo "[${index}/${total}] ${p12_path} generated; import the new file to authenticate. Password: immich"
    # pair is up to date with the current key.
    elif verify_mtls_pair "$key_val" "$ca_crt_path" "$p12_path" "$p12_password"; then
        echo "[${index}/${total}] ${p12_path} is up to date; existing file continues to authenticate. Password: immich"
    # pair failed verification; archive it under its old key, rebuild.
    else
        local rotated_key_segment=$(printf '%s' "${old_ca_key:64}" | grep -oE '[A-Za-z0-9]{12,}' | head -n1 | cut -c1-20)
        mv "$p12_path" "$(dirname "$p12_path")/${rotated_key_segment}-$(basename "$p12_path")"
        mv "$ca_crt_path" "$(dirname "$ca_crt_path")/${rotated_key_segment}-$(basename "$ca_crt_path")"
        gen_mtls_pair "$key_val" "$ca_crt_path" "$p12_path" "$p12_password"
        echo "[${index}/${total}] ${p12_path} rotated (old key pair files kept); import the new file to maintain authentication. Password: immich"
    fi
}

# --- verify_mtls_pair (returns: 0=up to date, 1=stale) -------------------------
verify_mtls_pair() {
    local key_val="$1" ca_crt_path="$2" p12_path="$3" p12_password="$4"

    # On-disk CA cert must match the current env CA key.
    local current_pub=$(printf '%s' "$key_val" | base64 -d | openssl rsa -pubout 2>/dev/null || true)
    local existing_pub=$(openssl x509 -in "$ca_crt_path" -noout -pubkey 2>/dev/null || true)
    if [ -z "$current_pub" ] || [ "$current_pub" != "$existing_pub" ]; then
        return 1   # CA in env no longer matches on-disk cert (rotated or drifted)
    fi

    # The p12's client cert must chain to that CA (catches stale/synced-back bundles).
    local client_cert="/tmp/_mtls_p12_check.crt"
    if ! openssl pkcs12 -in "$p12_path" -passin "pass:${p12_password}" -nokeys -clcerts 2>/dev/null \
        | openssl x509 -out "$client_cert" 2>/dev/null; then
        rm -f "$client_cert"; return 1   # p12 unreadable or corrupt ; treat as stale
    fi
    if ! openssl verify -CAfile "$ca_crt_path" "$client_cert" >/dev/null 2>&1; then
        rm -f "$client_cert"; return 1   # client cert chains to a different (older) CA
    fi
    rm -f "$client_cert"
    return 0
}

gen_mtls_pair() {
    local key_val="$1" ca_crt_path="$2" p12_path="$3" p12_password="$4"
    local ca_key="/tmp/_mtls_ca.key"
    local key_pem="/tmp/_mtls_client.key"
    local cert_pem="/tmp/_mtls_client.crt"
    local serial="/tmp/_mtls_ca.srl"

    # Decode CA private key from env var value
    printf '%s' "$key_val" | base64 -d > "$ca_key"

    # Write 002-immich-server.crt to storage (used for Caddy trust_pool + p12 bundle)
    openssl req -new -x509 -nodes -days 3650 -sha256 \
        -subj "/CN=DiwanSync Root CA" -key "$ca_key" \
        -out "$ca_crt_path"

    # Generate client key + sign (LibreSSL-compatible pipe)
    openssl genrsa 2048 2>/dev/null > "$key_pem"
    openssl req -new -key "$key_pem" \
        -subj "/CN=immich-mobile" 2>/dev/null | openssl x509 -req \
        -CA "$ca_crt_path" -CAkey "$ca_key" \
        -CAserial "$serial" -CAcreateserial -out "$cert_pem" -days 3650 2>/dev/null

    # Package PKCS#12 with client cert + CA cert in the bundle
    openssl pkcs12 -export -in "$cert_pem" \
        -inkey "$key_pem" -certfile "$ca_crt_path" \
        -out "$p12_path" -passout pass:${p12_password} 2>/dev/null

    rm -f "$ca_key" "$serial" "$key_pem" "$cert_pem"
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
