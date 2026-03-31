#!/bin/bash

source "$(dirname "$0")/config/user_manager.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DATE_READABLE=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname)
CSV_FILE="$(dirname "$0")/config/users.csv"

mkdir -p "$(dirname "$LOG_FILE")" "$KEYS_DIR"

log() {
    echo "[$DATE_READABLE] [$1] $2" | tee -a "$LOG_FILE"
}

print_header() {
    echo ""
    echo -e "${BLUE}=======================================${NC}"
    echo -e "${BLUE}  User Management — $HOSTNAME${NC}"
    echo -e "${BLUE}  $DATE_READABLE${NC}"
    echo -e "${BLUE}=======================================${NC}"
    echo ""
}

# ── Generate a random password ───────────────────────────
generate_password() {
    tr -dc 'A-Za-z0-9!@#$%' < /dev/urandom | head -c "$PASSWORD_LENGTH"
}

# ── Create a single user ─────────────────────────────────
create_user() {
    local username="$1"
    local group="$2"
    local sudo_access="$3"
    local shell="$4"

    echo -e "${BLUE}[INFO]  Processing user: $username${NC}"

    # Check if user already exists
    if id "$username" &>/dev/null; then
        echo -e "${YELLOW}[SKIP]  User already exists: $username${NC}"
        log "SKIP" "User already exists: $username"
        return
    fi

    # Create group if it doesn't exist
    if ! getent group "$group" &>/dev/null; then
        groupadd "$group"
        echo -e "${GREEN}[OK]    Group created: $group${NC}"
        log "OK" "Group created: $group"
    fi

    # Generate password
    local password
    password=$(generate_password)

    # Create the user
    if useradd -m -s "$shell" -g "$group" "$username" 2>/dev/null; then
        # Set password
        echo "$username:$password" | chpasswd 2>/dev/null

        echo -e "${GREEN}[OK]    User created: $username (group: $group)${NC}"
        log "OK" "User created: $username | group: $group | shell: $shell"

        # Save credentials securely
        local cred_file="./logs/credentials_${username}.txt"
        {
            echo "Username : $username"
            echo "Password : $password"
            echo "Group    : $group"
            echo "Shell    : $shell"
            echo "Created  : $DATE_READABLE"
        } > "$cred_file"
        chmod 600 "$cred_file"
        echo -e "${GREEN}[OK]    Credentials saved: $cred_file${NC}"

    else
        echo -e "${RED}[ERROR] Failed to create user: $username${NC}"
        log "ERROR" "Failed to create user: $username"
        return
    fi

    # Grant sudo access if requested
    if [ "$sudo_access" = "yes" ]; then
        setup_sudo "$username"
    fi

    # Generate SSH key pair
    generate_ssh_key "$username"
}

# ── Setup sudo access ────────────────────────────────────
setup_sudo() {
    local username="$1"
    local sudoers_file="/etc/sudoers.d/$username"

    if echo "$username ALL=(ALL) NOPASSWD:ALL" > "$sudoers_file" 2>/dev/null; then
        chmod 440 "$sudoers_file"
        echo -e "${GREEN}[OK]    Sudo granted: $username${NC}"
        log "OK" "Sudo access granted: $username"
    else
        echo -e "${YELLOW}[WARN]  Could not grant sudo (need root): $username${NC}"
        log "WARN" "Sudo grant skipped (no root): $username"
    fi
}

# ── Generate SSH key pair ────────────────────────────────
generate_ssh_key() {
    local username="$1"
    local key_dir="${KEYS_DIR}/${username}"

    mkdir -p "$key_dir"

    ssh-keygen -t ed25519 \
        -C "${username}@${HOSTNAME}" \
        -f "${key_dir}/id_ed25519" \
        -N "" -q 2>/dev/null

    if [ -f "${key_dir}/id_ed25519" ]; then
        echo -e "${GREEN}[OK]    SSH key generated: ${key_dir}/id_ed25519${NC}"
        log "OK" "SSH key generated for: $username → ${key_dir}/id_ed25519"

        # Copy public key to user's authorized_keys if user exists on system
        if id "$username" &>/dev/null; then
            local auth_dir="/home/${username}/.ssh"
            mkdir -p "$auth_dir" 2>/dev/null
            cp "${key_dir}/id_ed25519.pub" "${auth_dir}/authorized_keys" 2>/dev/null
            chmod 700 "$auth_dir" 2>/dev/null
            chmod 600 "${auth_dir}/authorized_keys" 2>/dev/null
            chown -R "$username:$username" "$auth_dir" 2>/dev/null
        fi
    else
        echo -e "${YELLOW}[WARN]  SSH key generation failed for: $username${NC}"
        log "WARN" "SSH key generation failed: $username"
    fi
}

# ── Delete a user ────────────────────────────────────────
delete_user() {
    local username="$1"

    if ! id "$username" &>/dev/null; then
        echo -e "${YELLOW}[SKIP]  User does not exist: $username${NC}"
        return
    fi

    if userdel -r "$username" 2>/dev/null; then
        echo -e "${GREEN}[OK]    User deleted: $username${NC}"
        log "OK" "User deleted: $username"

        # Remove sudoers entry
        rm -f "/etc/sudoers.d/$username"
        # Remove SSH keys
        rm -rf "${KEYS_DIR}/${username}"
    else
        echo -e "${YELLOW}[WARN]  Could not delete (need root): $username${NC}"
        log "WARN" "Delete skipped (no root): $username"
    fi
}

# ── List all users from CSV ──────────────────────────────
list_users() {
    echo ""
    echo -e "${BLUE}Users defined in $CSV_FILE:${NC}"
    echo ""
    echo -e "  ${BLUE}USERNAME       GROUP          SUDO    SHELL${NC}"
    echo    "  ─────────────────────────────────────────────────"
    tail -n +2 "$CSV_FILE" | while IFS=',' read -r username group sudo shell; do
        local status
        if id "$username" &>/dev/null; then
            status="${GREEN}[exists]${NC}"
        else
            status="${YELLOW}[missing]${NC}"
        fi
        printf "  %-14s %-14s %-7s %-15s " "$username" "$group" "$sudo" "$shell"
        echo -e "$status"
    done
    echo ""
}

# ── Audit report ─────────────────────────────────────────
show_audit() {
    echo ""
    echo -e "${BLUE}Audit log — $LOG_FILE:${NC}"
    echo ""
    if [ -f "$LOG_FILE" ]; then
        cat "$LOG_FILE"
    else
        echo "  No audit log found."
    fi
    echo ""
}

# ── Process all users from CSV ───────────────────────────
process_csv() {
    if [ ! -f "$CSV_FILE" ]; then
        echo -e "${RED}[ERROR] CSV file not found: $CSV_FILE${NC}"
        exit 1
    fi

    local total=0
    local skipped=0

    # Skip header line
    tail -n +2 "$CSV_FILE" | while IFS=',' read -r username group sudo shell; do
        # Skip empty lines
        [ -z "$username" ] && continue
        create_user "$username" "$group" "$sudo" "$shell"
        total=$((total + 1))
    done

    echo ""
    log "INFO" "CSV processing complete"
}

# ── Main ─────────────────────────────────────────────────
print_header

case "$1" in
    --create)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 --create <username> <group> [sudo:yes/no]"
            exit 1
        fi
        create_user "$2" "$3" "${4:-no}" "${DEFAULT_SHELL}"
        ;;
    --delete)
        if [ -z "$2" ]; then
            echo "Usage: $0 --delete <username>"
            exit 1
        fi
        delete_user "$2"
        ;;
    --list)
        list_users
        ;;
    --audit)
        show_audit
        ;;
    --csv)
        process_csv
        ;;
    --help)
        echo ""
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "  --csv              process all users from config/users.csv"
        echo "  --create u g [s]   create one user (group, optional sudo)"
        echo "  --delete u         delete a user"
        echo "  --list             list all users from CSV"
        echo "  --audit            show audit log"
        echo "  --help             show this help"
        echo ""
        ;;
    *)
        echo -e "${YELLOW}No option given. Use --help to see usage.${NC}"
        echo ""
        list_users
        ;;
esac
