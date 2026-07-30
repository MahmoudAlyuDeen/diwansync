#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

USERS_DB="storage/volumes/004-dyngress/authelia/users_database.yml"

if [ ! -f "$USERS_DB" ]; then
    echo "✗ users_database.yml not found. Run ./setup.sh first."
    exit 1
fi

confirm() { local r; read -rp "$1 [y/n] " r; [[ "${r:-n}" == [Yy]* ]]; }

ask_password() {
    while true; do
        read -rsp "Password: " PASSWORD; echo ""
        read -rsp "Confirm password: " CONFIRM; echo ""
        if [ "$PASSWORD" = "$CONFIRM" ]; then
            break
        fi
        echo "  ✗ Passwords do not match. Try again (Ctrl+C to quit)."
    done

    local raw
    echo "  Hashing password..."
    raw=$(docker run --rm authelia/authelia:latest \
          authelia crypto hash generate argon2 \
          --password "$PASSWORD" --no-confirm 2>&1) || {
        echo "  ✗ Failed to generate password hash (is Docker running?)."; exit 1
    }
    HASH=$(printf '%s' "$raw" | sed -n 's/^Digest:[[:space:]]*//p') || true
    if [ -z "$HASH" ]; then
        echo "  ✗ Failed to parse password hash."; exit 1
    fi
}

list_users() {
    python3 - "$USERS_DB" <<'PYEOF'
import yaml, sys
db = yaml.safe_load(open(sys.argv[1]))
users = db.get('users', {})
if not users:
    print("  — no users yet")
else:
    for name, info in users.items():
        status = "enabled" if not info.get("disabled", False) else "DISABLED"
        print(f"  • {name:20} [{status}]")
PYEOF
}

user_exists() {
    local uname="$1"
    python3 - "$USERS_DB" <<PYEOF >/dev/null 2>&1
import yaml, sys
d = yaml.safe_load(open(sys.argv[1]))
exit(0 if '$uname' in d.get('users',{}) else 1)
PYEOF
}

user_write() {
    local uname="$1" hash="$2"
    python3 - "$USERS_DB" <<PYEOF >/dev/null 2>&1
import yaml, sys
with open(sys.argv[1]) as f: d = yaml.safe_load(f)
users = d.get('users', {})
entry = dict(disabled=False, password="$hash")
users["$uname"] = entry
d['users'] = users
with open(sys.argv[1], 'w') as f: yaml.dump(d, f, default_flow_style=False)
PYEOF
}

user_update_password() {
    local uname="$1" hash="$2"
    python3 - "$USERS_DB" <<PYEOF >/dev/null 2>&1
import yaml, sys
with open(sys.argv[1]) as f: d = yaml.safe_load(f)
users = d.get('users', {})
if "$uname" in users:
    users["$uname"]["password"] = "$hash"
d['users'] = users
with open(sys.argv[1], 'w') as f: yaml.dump(d, f, default_flow_style=False)
PYEOF
}

user_update_disabled() {
    local uname="$1"
    python3 - "$USERS_DB" <<PYEOF >/dev/null 2>&1
import yaml, sys
with open(sys.argv[1]) as f: d = yaml.safe_load(f)
u = d['users']['$uname']
d['users']['$uname']["disabled"] = not u.get("disabled", False)
with open(sys.argv[1], 'w') as f: yaml.dump(d, f, default_flow_style=False)
PYEOF
}

user_delete() {
    local uname="$1"
    python3 - "$USERS_DB" <<PYEOF >/dev/null 2>&1
import yaml, sys
with open(sys.argv[1]) as f: d = yaml.safe_load(f)
users = d.get('users', {})
if "$uname" in users:
    del users["$uname"]
d['users'] = users
with open(sys.argv[1], 'w') as f: yaml.dump(d, f, default_flow_style=False)
PYEOF
}

user_show_info() {
    local uname="$1"
    python3 - "$USERS_DB" <<PYEOF
import yaml, sys
d = yaml.safe_load(open(sys.argv[1]))
u = d['users']['$uname']
status = "enabled" if not u.get("disabled", False) else "DISABLED"
print(f"  User: $uname | {status}")
PYEOF
}

menu() {
    echo ""
    echo "  1) Generate new user credentials"
    echo "  2) Reset a user password"
    echo "  3) Toggle enable / disable a user"
    echo "  4) Delete a user"
    echo "  5) Quit"
    echo ""
}

while true; do
    list_users

    USER_COUNT=$(python3 -c "import yaml,sys; print(len(yaml.safe_load(open(sys.argv[1])).get('users',{})))" "$USERS_DB")

    echo ""
    if [ "$USER_COUNT" -gt 0 ]; then
        echo "  1) Generate new user credentials"
        echo "  2) Reset a user password"
        echo "  3) Toggle enable / disable a user"
        echo "  4) Delete a user"
        echo "  5) Quit"
    else
        echo "  1) Generate new user credentials"
        echo "  2) Quit"
    fi
    echo ""

    read -rp "Choose [1-$( [ "$USER_COUNT" -gt 0 ] && echo 5 || echo 2 )]: " choice

    case "${choice:-5}" in
        1)
            # === GENERATE NEW USER ===
            while true; do
                read -rp "Username: " username
                if [ -z "$username" ]; then echo "  Username is required."; continue; fi
                if user_exists "$username"; then
                    echo "  ✗ User '$username' already exists. (Ctrl+C to quit, or re-type)."
                else
                    break
                fi
            done

            ask_password
            HASH_MASKED="${HASH:0:8}…${HASH:(-20)}"
            echo ""
            echo "  ✓ Hash generated ($((${#HASH}-1)) chars)"

            user_write "$username" "$HASH" && \
                user_exists "$username" && \
                echo "  ✓ User '$username' created." || { echo "  ✗ Failed to write user."; exit 1; }
            ;;

        2)
            [ "$USER_COUNT" -eq 0 ] && { echo "  - Done."; exit 0; }
            # === RESET PASSWORD ===
            python3 - "$USERS_DB" <<'PYEOF'
import yaml, sys
db = yaml.safe_load(open(sys.argv[1]))
users = db.get('users', {})
for i, (name, info) in enumerate(users.items(), 1):
    status = "enabled" if not info.get("disabled", False) else "DISABLED"
    print(f"  {i}) {name:20} [{status}]")
PYEOF

            while true; do
                read -rp "User number: " usernum
                username=$(python3 - "$USERS_DB" "$usernum" <<'PYEOF'
import yaml, sys
try:
    idx = int(sys.argv[2]) - 1
    users = list(yaml.safe_load(open(sys.argv[1])).get('users', {}).keys())
    print(users[idx] if 0 <= idx < len(users) else "")
except (ValueError, IndexError):
    print("__INVALID__")
PYEOF
                ) || true
                [ -z "$username" ] && echo "  Invalid." && continue
                echo "  → $username"
                break
            done

            # Show current user details before reset
            user_show_info "$username"

            ask_password
            HASH_MASKED="${HASH:0:8}…${HASH:(-20)}"
            echo ""
            echo "  ✓ Hash generated ($((${#HASH}-1)) chars)"

            user_update_password "$username" "$HASH" && \
                echo "  ✓ Password reset for '$username'." || { echo "  ✗ Failed to update password."; exit 1; }
            ;;

        3)
            [ "$USER_COUNT" -eq 0 ] && { echo "  - Done."; exit 0; }
            # === TOGGLE ENABLE/DISABLE ===
            python3 - "$USERS_DB" <<'PYEOF'
import yaml, sys
db = yaml.safe_load(open(sys.argv[1]))
users = db.get('users', {})
for i, (name, info) in enumerate(users.items(), 1):
    status = "enabled" if not info.get("disabled", False) else "DISABLED"
    print(f"  {i}) {name:20} [{status}]")
PYEOF

            while true; do
                read -rp "User number: " usernum
                username=$(python3 - "$USERS_DB" "$usernum" <<'PYEOF'
import yaml, sys
try:
    idx = int(sys.argv[2]) - 1
    users = list(yaml.safe_load(open(sys.argv[1])).get('users', {}).keys())
    print(users[idx] if 0 <= idx < len(users) else "")
except (ValueError, IndexError):
    print("__INVALID__")
PYEOF
                ) || true
                [ -z "$username" ] && echo "  Invalid." && continue
                echo "  → $username"
                break
            done

            # Show current state
            python3 - "$USERS_DB" <<PYEOF
import yaml, sys
d = yaml.safe_load(open(sys.argv[1]))
u = d['users']['$username']
status = "enabled" if not u.get("disabled", False) else "DISABLED"
print(f"  Current status: {status}")
if u.get("disabled", False):
    print("  → will ENABLE")
else:
    print("  → will DISABLE")
PYEOF

            if ! confirm "  Proceed?"; then
                echo "  - cancelled."
            else
                if user_update_disabled "$username"; then
                    STATUS=$(python3 -c "
import yaml, sys
d = yaml.safe_load(open('$USERS_DB'))
u = d['users']['$username']
print('enabled' if not u.get('disabled', False) else 'DISABLED')
")
                    echo "  ✓ User '$username': $STATUS"
                else
                    echo "  ✗ Failed to toggle user."
                fi
            fi
            ;;

        4)
            [ "$USER_COUNT" -eq 0 ] && { echo "  - Done."; exit 0; }
            # === DELETE USER ===
            python3 - "$USERS_DB" <<'PYEOF'
import yaml, sys
db = yaml.safe_load(open(sys.argv[1]))
users = db.get('users', {})
for i, (name, info) in enumerate(users.items(), 1):
    status = "enabled" if not info.get("disabled", False) else "DISABLED"
    print(f"  {i}) {name:20} [{status}]")
PYEOF

            while true; do
                read -rp "User number to delete: " usernum
                username=$(python3 - "$USERS_DB" "$usernum" <<'PYEOF'
import yaml, sys
try:
    idx = int(sys.argv[2]) - 1
    users = list(yaml.safe_load(open(sys.argv[1])).get('users', {}).keys())
    print(users[idx] if 0 <= idx < len(users) else "")
except (ValueError, IndexError):
    print("__INVALID__")
PYEOF
                ) || true
                [ -z "$username" ] && echo "  Invalid." && continue
                echo "  → $username"
                break
            done

            # Show current state using python
            user_show_info "$username"

            if ! confirm "  This cannot be undone. Proceed?"; then
                echo "  - cancelled."
            else
                user_delete "$username" && \
                    echo "  ✓ User '$username' deleted." || echo "  ✗ Failed to delete user."
            fi
            ;;

        *)
            echo "  - Done."
            if [ "$(python3 -c "import yaml; d=yaml.safe_load(open('$USERS_DB')); print(len(d.get('users',{})))" 2>/dev/null || echo 0)" -eq 0 ]; then
                echo "    Services are accessible locally or via Tailscale without auth."
            else
                echo "    Run scripts/setup_authelia_user.sh again to manage users."
            fi
            exit 0
            ;;
    esac

done
