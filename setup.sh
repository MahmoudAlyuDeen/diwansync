#!/bin/bash
# Interactive storage setup: choose where persistent data lives, wire the
# `storage` pointer, seed it from storage.template, generate secrets, and
# optionally start the stack. The `storage` symlink is untracked (created
# here), so clones never carry a dangling link. See the README "Storage
# Architecture" section for details.
set -euo pipefail

cd "$(dirname "$0")"   # repo root
LINK="storage"

confirm() { local r; read -rp "$1 [y/N] " r; [[ "${r:-N}" == [Yy]* ]]; }

# Symlink $LINK -> target, creating the target (with sudo if needed).
link_to() {
    local target="$1"
    if [ -d "$LINK" ] && [ ! -L "$LINK" ]; then
        echo "An in-repo ./storage folder exists; move or remove it first."; exit 1
    fi
    if ! mkdir -p "$target" 2>/dev/null; then
        echo "Elevated permission needed to create $target"
        sudo mkdir -p "$target"
        sudo chown "$(id -u):$(id -g)" "$target"
    fi
    ln -sfn "$target" "$LINK"
    echo "  ✓ linked $LINK -> $target"
}

# --- 1. decide where storage lives ---
if [ -L "$LINK" ] || [ -d "$LINK" ]; then
    if [ -L "$LINK" ]; then here="$(readlink "$LINK")"; else here="<repo>/storage (in-repo folder)"; fi
    if confirm "Storage already points at $here. Keep it?"; then
        echo "  ✓ keeping $here"
    else
        [ -L "$LINK" ] && rm -f "$LINK"
        pick=1
    fi
else
    pick=1
fi

if [ "${pick:-0}" = 1 ]; then
    echo ""
    echo "Where should persisted data live? You can move it later."
    echo "  1) /mnt/diwanstorage"
    echo "  2) /diwanstorage"
    echo "  3) <repo>/storage         (testing only — untracked)"
    echo "  4) custom path"
    echo "  5) existing folder        (restore / another machine)"
    read -rp "Choose: " opt
    case "${opt:-1}" in
        1) link_to /mnt/diwanstorage ;;
        2) link_to /diwanstorage ;;
        3) mkdir -p "$LINK"; echo "  ✓ using in-repo ./storage (testing)" ;;
        4) read -rp "Absolute path: " target; link_to "$target" ;;
        5) read -rp "Path to your existing storage folder: " target
           [ -d "$target" ] || { echo "No such folder: $target"; exit 1; }
           [ -d "$LINK" ] && [ ! -L "$LINK" ] && { echo "An in-repo ./storage folder exists; move or remove it first."; exit 1; }
           ln -sfn "$target" "$LINK"; echo "  ✓ linked $LINK -> $target" ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi

# --- 2. seed template (non-destructive) ---
echo ""
if confirm "Populate storage from storage.template? Won't overwrite."; then
    cp -Rn ./storage.template/* "$LINK"/ 2>/dev/null || true
    echo "  ✓ seeded storage.template"
else
    echo "Skipped seeding."
fi

# --- 3. generate secrets ---
echo ""
if confirm "Generate secrets now?"; then
    bash scripts/generate_secrets.sh
else
    echo "Skipped generate_secrets."
fi

# --- 4. start the stack ---
echo ""
if confirm "Start the stack now (docker compose up -d)?"; then
    if ! command -v docker >/dev/null 2>&1; then
        echo "  ! docker not found — install it, then run 'docker compose up -d'."
    elif ! docker compose up -d; then
        echo "  ! 'docker compose up -d' failed — check the output above."
    fi
else
    echo "Skipped. Run 'docker compose up -d' when ready."
fi
