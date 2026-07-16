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
    if ! mkdir -p "$target" 2>/dev/null; then
        echo "Elevated permission needed to create $target"
        sudo mkdir -p "$target"
        sudo chown "$(id -u):$(id -g)" "$target"
    fi
    ln -sfn "$target" "$LINK"
    echo "  ✓ added storage symlink at repo root -> $target"
}

# --- 1. decide where storage lives ---
if [ -L "$LINK" ] && [ ! -e "$LINK" ]; then
    echo "  ! storage is a broken symlink -> $(readlink "$LINK") (target missing)."
    echo "    The target may just be offline — a disconnected network share, an unplugged disk, or the folder moved/renamed."
    echo "  1) Exit to reconnect it."
    echo "  2) Start over and pick another location (backs up the broken symlink)."
    read -rp "Choose: " dl
    if [ "${dl:-1}" = 2 ]; then
        backup="${LINK}-symlink-backup-$(date +%Y%m%d-%H%M%S)"
        mv "$LINK" "$backup"
        echo "  ✓ backed up the broken link -> ${backup}"
        pick=1
    else
        echo "Exiting. Reconnect the target, then re-run ./setup.sh."
        exit 0
    fi
elif [ -L "$LINK" ] || [ -d "$LINK" ]; then
    if [ -L "$LINK" ]; then here="$(readlink "$LINK")"; else here="<repo>/storage (in-repo folder)"; fi
    echo "Storage already points at $here."
    echo "  1) Keep it."
    echo "  2) Back it up and pick a new location."
    read -rp "Choose: " ka
    if [ "${ka:-1}" = 2 ]; then
        if [ -L "$LINK" ]; then
            backup="${LINK}-symlink-backup-$(date +%Y%m%d-%H%M%S)"
        else
            echo "  ! ${LINK}/ is a real in-repo folder and may hold live data (media, database, secrets)."
            backup="${LINK}-backup-$(date +%Y%m%d-%H%M%S)"
        fi
        mv "$LINK" "$backup"
        echo "  ✓ backed up ${LINK} -> ${backup}"
        pick=1
    else
        echo "  ✓ keeping $here"
    fi
else
    pick=1
fi

if [ "${pick:-0}" = 1 ]; then
    while :; do
        echo ""
        echo "Where should persisted data live? You can move it later."
        echo "  1) /diwanstorage"
        echo "  2) /mnt/diwanstorage"
        echo "  3) /srv/diwanstorage"
        echo "  4) /storage"
        echo "  5) <repo>/storage         (testing only — untracked)"
        echo "  6) custom path"
        echo "  7) existing folder        (restore / another machine)"
        read -rp "Choose: " opt
        case "${opt:-1}" in
            1) link_to /diwanstorage ;;
            2) link_to /mnt/diwanstorage ;;
            3) link_to /srv/diwanstorage ;;
            4) link_to /storage ;;
            5) mkdir -p "$LINK"; echo "  ✓ using in-repo ./storage (testing)" ;;
            6) read -rp "Absolute path: " target; link_to "$target" ;;
            7) read -rp "Path to your existing storage folder: " target
               if [ ! -d "$target" ]; then
                   echo "  ! $target isn't available right now."
                   echo "    It may be offline — a disconnected network share, an unplugged disk, or the folder moved/renamed."
                   echo "    Reconnect it, or start over and pick another location."
                   confirm "  Start over? (No = exit)" || { echo "Exiting. Reconnect the folder, then re-run ./setup.sh."; exit 0; }
                   continue
               fi
               ln -sfn "$target" "$LINK"; echo "  ✓ added storage symlink at repo root -> $target" ;;
            *) echo "Invalid choice"; exit 1 ;;
        esac
        break
    done
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
