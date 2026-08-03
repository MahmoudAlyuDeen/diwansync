#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

USERS_DB="storage/volumes/004-dyngress/authelia/users_database.yml"
AUTHELIA_DOCKER_IMAGE="authelia/authelia:latest"

# --- menu ------------------------------------------------------------------

print_user_list() {
    local user_list="$1"

    clear   # wipe screen before re-rendering table

    echo ""
    echo "$USERS_DB"
    echo ""

    if [ -n "$user_list" ]; then
        while IFS=$'\t' read -r idx name status; do
            echo "  $idx. $name [$status]"
        done <<< "$user_list"
    else
        echo "  — no users yet"
    fi

    # Pass same raw param to menu
    menu "$user_list"
}

menu() {
    local user_list="$1"

    if [ -n "$user_list" ]; then
        echo ""
        echo "  1) Create user"
        echo "  2) Reset user password"
        echo "  3) Enable a user"
        echo "  4) Disable a user"
        echo "  5) Delete a user"
        echo "  6) Quit"

        read -rp "Choose [1-6]: " CHOICE
    else
        echo ""
        echo "  1) Create user"
        echo "  2) Quit"

        read -rp "Choose [1-2]: " CHOICE
    fi

    case "$CHOICE" in
        1) create "$user_list" ;;     # mutation → fetches fresh data → print_user_list → menu (recursive cycle)
        2) [[ ${#user_list} -gt 0 ]] && reset_password "$user_list" || exit 0 ;;
        3) enable_user "$user_list" ;;
        4) disable_user "$user_list" ;;
        5) delete_user "$user_list" ;;
        *) echo "$(msg_invalid_choice)"; sleep 2; menu "$user_list" ;;   # recursive re-entry (NOT a loop)
    esac
}

# --- user operations -------------------------------------------------------
create() {
    local user_list="$1"

    while true; do
        read -rp "$(msg_prompt_username)" username
        [ -z "$username" ] && { echo "$(msg_user_required)"; continue; }
        [[ "$username" =~ ^[a-z]+$ ]] || { echo "  Username must contain only lowercase letters."; continue; }
        local existing_usernames
        existing_usernames=$(printf '%s\n' "$user_list" | cut -f2)
        [[ "$existing_usernames" == *"$username"* ]] && { echo "$(msg_user_already_exists $username)"; continue; }
        break
    done

    local HASH=$(get_password_hash_from_input)

    local mutation="user_entries['${username}'] = dict(disabled=False, password='${HASH}')"
    updated_user_list=$(perform_database_operation "$mutation")
    echo "$(msg_done)"

    sleep 2
    print_user_list "$updated_user_list"
}

reset_password() {
    local user_list="$1"
    local USERNAME_SELECTED=$(select_user "$user_list")

    echo "  → User: $USERNAME_SELECTED"

    local HASH=$(get_password_hash_from_input)

    local mutation="if \"${USERNAME_SELECTED}\" in user_entries: user_entries[\"${USERNAME_SELECTED}\"][\"password\"] = \"${HASH}\""
    updated_user_list=$(perform_database_operation "$mutation")
    echo "$(msg_done)"

    sleep 2
    print_user_list "$updated_user_list"
}

enable_user() {
    local user_list="$1"
    local USERNAME_SELECTED=$(select_user "$user_list")
    echo "  → will ENABLE ($USERNAME_SELECTED)"
    local updated_user_list="$user_list"
    if confirm "  Proceed? [y/n]"; then
        local mutation="if \"${USERNAME_SELECTED}\" in user_entries: user_entries[\"${USERNAME_SELECTED}\"][\"disabled\"] = False"
        updated_user_list=$(perform_database_operation "$mutation")
        echo "$(msg_done)"
    else
        echo "$(msg_cancelled)"
    fi

    sleep 2
    print_user_list "$updated_user_list"
}

disable_user() {
    local user_list="$1"
    local USERNAME_SELECTED=$(select_user "$user_list")
    echo "  → will DISABLE ($USERNAME_SELECTED)"
    local updated_user_list="$user_list"
    if confirm "  Proceed? [y/n]"; then
        local mutation="if \"${USERNAME_SELECTED}\" in user_entries: user_entries[\"${USERNAME_SELECTED}\"][\"disabled\"] = True"
        updated_user_list=$(perform_database_operation "$mutation")
        echo "$(msg_done)"
    else
        echo "$(msg_cancelled)"
    fi

    sleep 2
    print_user_list "$updated_user_list"
}

delete_user() {
    local user_list="$1"
    local USERNAME_SELECTED=$(select_user "$user_list")
    echo "  → User: $USERNAME_SELECTED"
    local updated_user_list="$user_list"
    if confirm "  This cannot be undone. Proceed? [y/n]"; then
        local mutation="user_entries.pop(\"${USERNAME_SELECTED}\", None)"
        updated_user_list=$(perform_database_operation "$mutation")
        echo "$(msg_done)"
    else
        echo "$(msg_cancelled)"
    fi

    sleep 2
    print_user_list "$updated_user_list"
}

# select_user <user_list>  → prints selected username to stdout; re-prompts until valid
select_user() {
    local user_list="$1"
    while true; do
        read -rp "$(msg_prompt_user_number) " input_number
        [[ $input_number =~ ^[0-9]+$ ]] || continue
        local selected_line
        selected_line=$(printf '%s\n' "$user_list" | sed -n "${input_number}p")
        [ -z "$selected_line" ] && { echo "$(msg_invalid_choice)" >&2; continue; }
        printf '%s\n' "$(printf '%s' "$selected_line" | cut -f2)"
        break
    done
}

# helpers ---------------------------------------------------------------

# confirm <prompt_string>  → return 0 if user types y/Y, 1 otherwise; defaults to n on empty enter
confirm() {
    local response
    read -rp "$1 [y/n] " response
    [[ "${response:-n}" == [Yy]* ]]
}

# perform_database_operation <expr>  → writes YAML atomically to $USERS_DB and prints updated user list to stdout
perform_database_operation() {
    local output
    if ! output=$(python3 - "$1" "${USERS_DB}" << 'PYEOF' 2>&1
import sys, yaml
from pathlib import Path

user_entries = list(yaml.safe_load_all(Path(sys.argv[2]).read_text("utf-8"))) or []
user_entries = user_entries[0] if user_entries else {}

mutation_expression = sys.argv[1] if len(sys.argv) > 1 else ""

if mutation_expression:
    namespace = {
        "sys": __import__("sys"),
        "yaml": yaml,
        "users_database": user_entries,
    }
    exec(mutation_expression, {}, namespace)
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        yaml.dump(user_entries, f, default_flow_style=False, allow_unicode=True)

for idx, (name, info) in enumerate(user_entries.items(), 1):
    status = "enabled" if not info.get("disabled", False) else "DISABLED"
    print(f"{idx}\t{name}\t{status}")
PYEOF
    ); then
        echo "" >&2
        echo "$(msg_db_operation_failed)" >&2
        return 1
    fi
    printf '%s\n' "$output"
}

# get_password_hash_from_input  → reads password interactively (stdin), prints hash to stdout; exit 1 if Docker missing or cancelled
get_password_hash_from_input() {
    while true; do
        read -rsp "$(msg_prompt_password)" PASSWORD >&2; echo "" >&2
        read -rsp "$(msg_prompt_confirm_pwd)" CONFIRM >&2; echo "" >&2
        [ -n "$PASSWORD" ] && [ "$PASSWORD" = "$CONFIRM" ] && break
        echo "  ✗ $(msg_pwd_mismatch)" >&2
    done

    local docker_output
    echo "  Hashing password..." >&2
    command -v docker >/dev/null 2>&1 || { echo "  ✗ $(msg_docker_hash_required)" >&2; return 1; }
    docker_output=$(docker run --rm "$AUTHELIA_DOCKER_IMAGE" \
          authelia crypto hash generate argon2 \
          --password "$PASSWORD" --no-confirm 2>&1) || { echo "  ✗ $(msg_docker_hash_required)" >&2; return 1; }
    printf '%s' "${docker_output#*Digest:}" | tr -d '[:space:]'   # stdout = only the hash
}

# --- display strings (bottom for quick scanning/editing) -------------------
msg_done()                   { echo "  ✓ Done"; }

msg_prompt_username()        { echo "Username:"; }
msg_prompt_password()        { echo "Password:"; }
msg_prompt_confirm_pwd()     { echo "Confirm password:"; }
msg_prompt_user_number()     { echo "Enter user number:"; }

msg_user_required()          { echo "Username is required."; }
msg_invalid_choice()         { echo "Invalid choice. Try again (Ctrl+C to quit)."; }
msg_user_already_exists()    { echo "User '$1' already exists. Try again (Ctrl+C to quit)."; }
msg_pwd_mismatch()           { echo "Passwords do not match. Try again (Ctrl+C to quit)."; }

msg_db_operation_failed()    { echo "Database operation failed. Please ensure $USERS_DB exists,
    then run scripts/setup_authelia_user_reorder.sh again or edit it manually."; }

msg_cancelled()              { echo "  ✓ cancelled"; }
msg_docker_hash_required()   { echo "Docker is required to generate password hashes.
    Install it or start the daemon, then run scripts/setup_authelia_user_reorder.sh again."; }

# --- execution entry point -------------------------------------------------
user_list=$(perform_database_operation "")
print_user_list "$user_list"
