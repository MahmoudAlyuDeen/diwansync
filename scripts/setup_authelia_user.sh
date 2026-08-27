#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root

USERS_DB="storage/volumes/004-dyngress/authelia/users_database.yml"
AUTHELIA_DOCKER_IMAGE="authelia/authelia:latest"

# --- menu ------------------------------------------------------------------

print_user_list() {
    local user_list="$1"

    clear   # wipe screen before re-rendering table

    echo "$USERS_DB"
    echo ""

    if [ -n "$user_list" ]; then
        while IFS=$'\t' read -r idx name status; do
            echo "$idx. $name [$status]"
        done <<< "$user_list"
    else
        echo "— no users yet"
    fi

    # Pass same raw param to menu
    menu "$user_list"
}

menu() {
    local user_list="$1"

    if [[ -n "$user_list" ]]; then
        echo ""
        echo "↓ Choose an action ↓"
        echo "1) Add a user"
        echo "2) Reset a user password"
        echo "3) Enable a user"
        echo "4) Disable a user"
        echo "5) Delete a user"
        echo "6) Quit"

        while true; do
            local CHOICE
            read -rp "Choose [1-6]: " CHOICE
            case "$CHOICE" in
                1) create "$user_list"; break ;;
                2) reset_password "$user_list"; break ;;
                3) enable_user "$user_list"; break ;;
                4) disable_user "$user_list"; break ;;
                5) delete_user "$user_list"; break ;;
                6) exit 0 ;;
                *) msg_invalid_choice ;;
            esac
        done

    else
        echo ""
        echo "↓ Choose an action ↓"
        echo "1) Add a user"
        echo "2) Quit"

        while true; do
            local CHOICE
            read -rp "Choose [1-2]: " CHOICE
            case "$CHOICE" in
                1) create "$user_list"; break ;;
                2) exit 0 ;;
                *) msg_invalid_choice ;;
            esac
        done
    fi
}

# --- user operations -------------------------------------------------------
create() {
    local user_list="$1"

    local email_regex='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'

    while true; do
        read -rp "$(msg_prompt_email)" email_input
        [[ "$email_input" =~ $email_regex ]] || { msg_email_invalid; continue; }

        # Use email as-is for all three fields (lowercased)
        email_input=$(printf '%s' "$email_input" | tr '[:upper:]' '[:lower:]')

        # Duplicate check against existing usernames in DB
        local existing_usernames
        existing_usernames=$(printf '%s\n' "$user_list" | cut -f2)
        [[ "$existing_usernames" == *"$email_input"* ]] && { msg_user_already_exists "$email_input"; continue; }
        break
    done

    local HASH=$(get_password_hash_from_input)

    local mutation="user_entries['${email_input}'] = dict(email='$email_input', displayname='${email_input}', disabled=False, password='${HASH}')"
    updated_user_list=$(perform_database_operation "$mutation")
    msg_done

    sleep 2
    print_user_list "$updated_user_list"
}

reset_password() {
    local user_list="$1"
    local USERNAME_SELECTED=$(select_user "$user_list")

    echo "→ User: $USERNAME_SELECTED"

    local HASH=$(get_password_hash_from_input)

    local mutation="if \"${USERNAME_SELECTED}\" in user_entries: user_entries[\"${USERNAME_SELECTED}\"][\"password\"] = \"${HASH}\""
    updated_user_list=$(perform_database_operation "$mutation")
    msg_done

    sleep 2
    print_user_list "$updated_user_list"
}

enable_user() {
    local user_list="$1"
    local USERNAME_SELECTED=$(select_user "$user_list")
    echo "→ will ENABLE ($USERNAME_SELECTED)"
    local updated_user_list="$user_list"
    if confirm "Proceed?"; then
        local mutation="if \"${USERNAME_SELECTED}\" in user_entries: user_entries[\"${USERNAME_SELECTED}\"][\"disabled\"] = False"
        updated_user_list=$(perform_database_operation "$mutation")
        msg_done
    else
        msg_cancelled
    fi

    sleep 2
    print_user_list "$updated_user_list"
}

disable_user() {
    local user_list="$1"
    local USERNAME_SELECTED=$(select_user "$user_list")
    echo "→ will DISABLE ($USERNAME_SELECTED)"
    local updated_user_list="$user_list"
    if confirm "Proceed?"; then
        local mutation="if \"${USERNAME_SELECTED}\" in user_entries: user_entries[\"${USERNAME_SELECTED}\"][\"disabled\"] = True"
        updated_user_list=$(perform_database_operation "$mutation")
        msg_done
    else
        msg_cancelled
    fi

    sleep 2
    print_user_list "$updated_user_list"
}

delete_user() {
    local user_list="$1"
    local USERNAME_SELECTED=$(select_user "$user_list")
    echo "→ User: $USERNAME_SELECTED"
    local updated_user_list="$user_list"
    if confirm "This cannot be undone. Proceed?"; then
        local mutation="user_entries.pop(\"${USERNAME_SELECTED}\", None)"
        updated_user_list=$(perform_database_operation "$mutation")
        msg_done
    else
        msg_cancelled
    fi

    sleep 2
    print_user_list "$updated_user_list"
}

select_user() {
    local user_list="$1"
    while true; do
        read -rp "$(msg_prompt_user_number) " input_number
        [[ $input_number =~ ^[0-9]+$ ]] || continue
        local selected_line
        selected_line=$(printf '%s\n' "$user_list" | sed -n "${input_number}p")
        [ -z "$selected_line" ] && { msg_invalid_choice >&2; continue; }
        printf '%s\n' "$(printf '%s' "$selected_line" | cut -f2)"
        break
    done
}

# helpers ---------------------------------------------------------------

confirm() {
    local response
    read -rp "$1 [y/n] " response
    [[ "${response:-n}" == [Yy]* ]]
}

perform_database_operation() {
    local output
    if ! output=$(python3 - "$1" "${USERS_DB}" << 'PYEOF' 2>&1
import sys, yaml

database_mutation = sys.argv[1]
users_database_file = sys.argv[2]
USERS_KEY = "users"

user_entries = yaml.safe_load(open(users_database_file).read())[USERS_KEY]

if database_mutation:
    namespace = {
        "sys": __import__("sys"),
        "yaml": yaml,
        "user_entries": user_entries,
    }
    exec(database_mutation, {}, namespace)
    with open(users_database_file, "w", encoding="utf-8") as f:
        yaml.dump(
            {USERS_KEY: user_entries},
            f, default_flow_style=False, allow_unicode=True
        )

for idx, (name, info) in enumerate(user_entries.items(), 1):
    status = "enabled" if not info.get("disabled", False) else "DISABLED"
    email_val = info.get("email", "")
    label = email_val if email_val else name
    print(f"{idx}\t{label}\t{status}")
PYEOF
    ); then
        echo "" >&2
        msg_db_operation_failed >&2
        return 1
    fi
    printf '%s\n' "$output"
}

get_password_hash_from_input() {
    while true; do
        read -rsp "$(msg_prompt_password)" PASSWORD >&2; echo "" >&2
        read -rsp "$(msg_prompt_confirm_pwd)" CONFIRM >&2; echo "" >&2
        [ -n "$PASSWORD" ] && [ "$PASSWORD" = "$CONFIRM" ] && break
        msg_pwd_mismatch >&2
    done

    local docker_output
    echo "Hashing password..." >&2
    command -v docker >/dev/null 2>&1 || { msg_docker_hash_required >&2; return 1; }
    docker_output=$(docker run --rm "$AUTHELIA_DOCKER_IMAGE" \
          authelia crypto hash generate argon2 \
          --password "$PASSWORD" --no-confirm 2>&1) || { msg_docker_hash_required >&2; return 1; }
    printf '%s' "${docker_output#*Digest:}" | tr -d '[:space:]'
}

# --- display strings -----------------------------------------------------
msg_done()                   { echo "✓ Done"; }

msg_prompt_email()           { echo "Email:"; }
msg_prompt_password()        { echo "Password:"; }
msg_prompt_confirm_pwd()     { echo "Confirm password:"; }
msg_prompt_user_number()     { echo "Enter user number:"; }

msg_email_invalid()          { echo "Invalid email, must be a valid email, e.g: abc@xyz.tld.
This is needed to send authentication emails to allow user enrollement.
Try again (Ctrl+C to quit)."; }
msg_invalid_choice()         { echo "Invalid choice. Try again (Ctrl+C to quit)."; }
msg_user_already_exists()    { echo "User '$1' already exists. Try again (Ctrl+C to quit)."; }
msg_pwd_mismatch()           { echo "✗ Passwords do not match. Try again (Ctrl+C to quit)."; }

msg_db_operation_failed()    { echo "Database operation failed. Please ensure $USERS_DB exists,
    then run scripts/setup_authelia_user_reorder.sh again or edit it manually."; }

msg_cancelled()              { echo "✓ cancelled"; }
msg_docker_hash_required()   { echo "✗ Docker is required to generate password hashes.
    Install it or start the daemon, then run scripts/setup_authelia_user_reorder.sh again."; }

# --- execution entry point -------------------------------------------------
user_list=$(perform_database_operation "")
print_user_list "$user_list"
