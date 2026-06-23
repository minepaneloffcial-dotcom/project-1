#!/bin/bash

# =====================================================
#  TASIN VPS CONTROL PANEL v2.0
#  WITH GITHUB REMOTE MANAGEMENT & LICENSE SYSTEM
# =====================================================
#  Remote DB: https://raw.githubusercontent.com/
#    minepaneloffcial-dotcom/project-1/refs/heads/main/users-data
#
#  Data format (users-data file on GitHub):
#    LICENSE=your-license-key-here
#    hostname|password|ip|type
#    hostname|password|ip|type
#
#  Each VM line: hostname|root_password|assigned_ip|vps_or_vds
# =====================================================

# ==================================================
#       COLORS & UI CONSTANTS
# ==================================================
NC='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'

# ==================================================
#       LOG FILE SETUP
# ==================================================
LOG_FILE="/root/vm_manager.log"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ==================================================
#       GITHUB REMOTE CONFIG
# ==================================================
GITHUB_CONFIG_FILE="/root/.vm_github_config"
GITHUB_STATE_FILE="/root/.vm_remote_state"
GITHUB_LICENSE_CACHE="/root/.vm_license_cache"
SYNC_INTERVAL=60  # seconds between remote checks
SYNC_DAEMON_PID=""

# Default values (will be overwritten by config file)
GITHUB_TOKEN=""
GITHUB_REPO_OWNER="minepaneloffcial-dotcom"
GITHUB_REPO_NAME="project-1"
GITHUB_BRANCH="main"
GITHUB_DATA_FILE="users-data"

# Computed URLs
get_raw_url() {
    echo "https://raw.githubusercontent.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/${GITHUB_BRANCH}/${GITHUB_DATA_FILE}"
}
get_api_url() {
    echo "https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/contents/${GITHUB_DATA_FILE}"
}

# ==================================================
#       GITHUB CONFIG SETUP (First Run)
# ==================================================
load_github_config() {
    if [ -f "$GITHUB_CONFIG_FILE" ]; then
        source "$GITHUB_CONFIG_FILE"
        log_msg "GitHub config loaded from $GITHUB_CONFIG_FILE"
        return 0
    fi
    return 1
}

setup_github_config() {
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "    ${WHITE}GITHUB REMOTE MANAGEMENT SETUP${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e ""
    echo -e " ${YELLOW}This panel syncs VM data to a GitHub raw file.${NC}"
    echo -e " ${YELLOW}You need a GitHub Personal Access Token with repo access.${NC}"
    echo -e " ${YELLOW}Create one at: ${BLUE}https://github.com/settings/tokens${NC}"
    echo -e ""
    echo -e " ${WHITE}Repo: ${GREEN}${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}${NC}"
    echo -e " ${WHITE}Branch: ${GREEN}${GITHUB_BRANCH}${NC}"
    echo -e " ${WHITE}File: ${GREEN}${GITHUB_DATA_FILE}${NC}"
    echo -e ""

    echo -n " Enter GitHub Token: "
    read -r token_input
    if [ -z "$token_input" ]; then
        echo -e " ${RED}✘ Token is required for remote management.${NC}"
        echo -e " ${YELLOW}Running in LOCAL-ONLY mode. Remote sync disabled.${NC}"
        sleep 3
        REMOTE_ENABLED=false
        return
    fi

    echo -n " Enter Repo Owner [${GITHUB_REPO_OWNER}]: "
    read -r owner_input
    [ -n "$owner_input" ] && GITHUB_REPO_OWNER="$owner_input"

    echo -n " Enter Repo Name [${GITHUB_REPO_NAME}]: "
    read -r repo_input
    [ -n "$repo_input" ] && GITHUB_REPO_NAME="$repo_input"

    echo -n " Enter Branch [${GITHUB_BRANCH}]: "
    read -r branch_input
    [ -n "$branch_input" ] && GITHUB_BRANCH="$branch_input"

    echo -n " Enter Data File Name [${GITHUB_DATA_FILE}]: "
    read -r file_input
    [ -n "$file_input" ] && GITHUB_DATA_FILE="$file_input"

    echo -n " Sync Interval in seconds [${SYNC_INTERVAL}]: "
    read -r sync_input
    [ -n "$sync_input" ] && SYNC_INTERVAL="$sync_input"

    # Save config
    cat > "$GITHUB_CONFIG_FILE" << EOF
GITHUB_TOKEN="$token_input"
GITHUB_REPO_OWNER="$GITHUB_REPO_OWNER"
GITHUB_REPO_NAME="$GITHUB_REPO_NAME"
GITHUB_BRANCH="$GITHUB_BRANCH"
GITHUB_DATA_FILE="$GITHUB_DATA_FILE"
SYNC_INTERVAL=$SYNC_INTERVAL
EOF

    echo -e " ${GREEN}✔ GitHub config saved!${NC}"
    GITHUB_TOKEN="$token_input"
    REMOTE_ENABLED=true
    sleep 2

    # Test connection
    echo -e " ${YELLOW}Testing GitHub connection...${NC}"
    local test_data=$(fetch_remote_raw)
    if [ -n "$test_data" ]; then
        echo -e " ${GREEN}✔ Connected! Remote file found.${NC}"
    else
        echo -e " ${YELLOW}⚠ Remote file not found or empty. It will be created on first VM creation.${NC}"
    fi
    sleep 2
}

# ==================================================
#       GITHUB API FUNCTIONS
# ==================================================

# Fetch raw file content from GitHub
fetch_remote_raw() {
    local raw_url=$(get_raw_url)
    local response=$(curl -s -f -m 10 "$raw_url" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo "$response"
        return 0
    fi
    return 1
}

# Get file SHA and content via GitHub API (for updates)
github_api_get_file() {
    local api_url=$(get_api_url)
    local response=$(curl -s -f -m 10 \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "${api_url}?ref=${GITHUB_BRANCH}" 2>/dev/null)
    echo "$response"
}

# Push updated content to GitHub
github_api_push() {
    local content="$1"
    local message="$2"

    # Get current file SHA
    local api_response=$(github_api_get_file)
    local sha=""

    if [ -n "$api_response" ]; then
        sha=$(echo "$api_response" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('sha', ''))
except:
    pass
" 2>/dev/null)
    fi

    # Base64 encode the content
    local b64_content=$(echo "$content" | base64 -w 0)

    local api_url=$(get_api_url)
    local json_payload=$(python3 -c "
import json
print(json.dumps({
    'message': '$message',
    'content': '$b64_content',
    'sha': '$sha',
    'branch': '$GITHUB_BRANCH'
}))
" 2>/dev/null)

    local response=$(curl -s -f -m 15 \
        -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "$json_payload" \
        "$api_url" 2>/dev/null)

    if [ $? -eq 0 ]; then
        return 0
    else
        log_msg "GitHub API push failed: $response"
        return 1
    fi
}

# ==================================================
#       LICENSE SYSTEM
# ==================================================

# Parse license from remote data
extract_license() {
    local data="$1"
    echo "$data" | grep "^LICENSE=" | head -1 | cut -d'=' -f2-
}

# Validate current license against remote
validate_license() {
    if [ "$REMOTE_ENABLED" != true ]; then
        return 0  # No remote = skip license check
    fi

    local remote_data=$(fetch_remote_raw)
    if [ -z "$remote_data" ]; then
        echo -e " ${RED}✘ Cannot reach remote server. Retrying...${NC}"
        return 1
    fi

    local remote_license=$(extract_license "$remote_data")
    local cached_license=""

    if [ -f "$GITHUB_LICENSE_CACHE" ]; then
        cached_license=$(cat "$GITHUB_LICENSE_CACHE")
    fi

    # Case 1: License removed from remote
    if [ -z "$remote_license" ]; then
        log_msg "LICENSE REMOVED from remote. Shutting down all VMs."
        echo -e " ${RED}══════════════════════════════════════════════════${NC}"
        echo -e " ${RED}  ⚠ LICENSE REMOVED FROM REMOTE SERVER${NC}"
        echo -e " ${RED}  All VMs will be deleted. Script shutting down.${NC}"
        echo -e " ${RED}══════════════════════════════════════════════════${NC}"
        delete_all_vms
        rm -f "$GITHUB_LICENSE_CACHE"
        sleep 3
        exit 1
    fi

    # Case 2: License changed
    if [ -n "$cached_license" ] && [ "$cached_license" != "$remote_license" ]; then
        log_msg "LICENSE CHANGED: $cached_license -> $remote_license"
        echo -e " ${YELLOW}⚠ License key updated by remote admin.${NC}"
        echo "$remote_license" > "$GITHUB_LICENSE_CACHE"
        CURRENT_LICENSE="$remote_license"
        return 0
    fi

    # Case 3: First time or same license
    if [ -z "$cached_license" ]; then
        echo "$remote_license" > "$GITHUB_LICENSE_CACHE"
        CURRENT_LICENSE="$remote_license"
        log_msg "License initialized: $remote_license"
    fi

    return 0
}

# Get current license
CURRENT_LICENSE=""
if [ -f "$GITHUB_LICENSE_CACHE" ]; then
    CURRENT_LICENSE=$(cat "$GITHUB_LICENSE_CACHE")
fi

# ==================================================
#       REMOTE STATE MANAGEMENT
# ==================================================

# Save local VM state: container_name=hostname|password|ip|type
save_local_state() {
    local vm_name="$1"
    local hostname="$2"
    local password="$3"
    local ip="$4"
    local type="$5"

    # Remove old entry for this container
    if [ -f "$GITHUB_STATE_FILE" ]; then
        grep -v "^${vm_name}=" "$GITHUB_STATE_FILE" > "${GITHUB_STATE_FILE}.tmp" 2>/dev/null
        mv "${GITHUB_STATE_FILE}.tmp" "$GITHUB_STATE_FILE" 2>/dev/null
    fi

    echo "${vm_name}=${hostname}|${password}|${ip}|${type}" >> "$GITHUB_STATE_FILE"
    log_msg "State saved: $vm_name -> $hostname|$ip|$type"
}

# Remove VM from local state
remove_local_state() {
    local vm_name="$1"
    if [ -f "$GITHUB_STATE_FILE" ]; then
        grep -v "^${vm_name}=" "$GITHUB_STATE_FILE" > "${GITHUB_STATE_FILE}.tmp" 2>/dev/null
        mv "${GITHUB_STATE_FILE}.tmp" "$GITHUB_STATE_FILE" 2>/dev/null
    fi
    log_msg "State removed: $vm_name"
}

# Get local state for a container
get_local_state() {
    local vm_name="$1"
    if [ -f "$GITHUB_STATE_FILE" ]; then
        grep "^${vm_name}=" "$GITHUB_STATE_FILE" | head -1 | cut -d'=' -f2-
    fi
}

# Get password for a VM from local state
get_vm_password() {
    local state=$(get_local_state "$1")
    echo "$state" | cut -d'|' -f2
}

# Get IP for a VM from local state
get_vm_ip() {
    local state=$(get_local_state "$1")
    echo "$state" | cut -d'|' -f3
}

# Get all local state entries
get_all_local_state() {
    if [ -f "$GITHUB_STATE_FILE" ]; then
        cat "$GITHUB_STATE_FILE"
    fi
}

# ==================================================
#       REMOTE DATA OPERATIONS
# ==================================================

# Build remote file content from local VMs + license
build_remote_content() {
    local license="$CURRENT_LICENSE"
    local lines="LICENSE=${license}"

    if [ -f "$GITHUB_STATE_FILE" ]; then
        while IFS='=' read -r container_name vm_data; do
            [ -z "$vm_data" ] && continue
            local hostname=$(echo "$vm_data" | cut -d'|' -f1)
            local password=$(echo "$vm_data" | cut -d'|' -f2)
            local ip=$(echo "$vm_data" | cut -d'|' -f3)
            local type=$(echo "$vm_data" | cut -d'|' -f4)
            lines="${lines}
${hostname}|${password}|${ip}|${type}"
        done < "$GITHUB_STATE_FILE"
    fi

    echo "$lines"
}

# Push a new VM to the remote file
push_vm_to_remote() {
    local vm_name="$1"
    local hostname="$2"
    local password="$3"
    local ip="$4"
    local type="$5"

    [ "$REMOTE_ENABLED" != true ] && return

    log_msg "Pushing VM $hostname to remote..."

    # Build new content: current remote + new VM
    local remote_data=$(fetch_remote_raw)
    local license_line="LICENSE=${CURRENT_LICENSE}"
    local new_content=""

    if [ -n "$remote_data" ]; then
        # Keep existing license from remote
        local remote_license=$(extract_license "$remote_data")
        if [ -n "$remote_license" ]; then
            license_line="LICENSE=${remote_license}"
            CURRENT_LICENSE="$remote_license"
            echo "$remote_license" > "$GITHUB_LICENSE_CACHE"
        fi

        # Remove any existing entry with same hostname
        new_content=$(echo "$remote_data" | grep -v "^${hostname}|")
    else
        new_content=""
    fi

    # Build final content
    local final_content="${license_line}"
    if [ -n "$new_content" ]; then
        final_content="${final_content}
${new_content}"
    fi
    final_content="${final_content}
${hostname}|${password}|${ip}|${type}"

    if github_api_push "$final_content" "Add VM: $hostname"; then
        log_msg "VM $hostname pushed to remote successfully."
    else
        log_msg "WARNING: Failed to push VM $hostname to remote."
    fi
}

# Remove a VM from the remote file
remove_vm_from_remote() {
    local hostname="$1"

    [ "$REMOTE_ENABLED" != true ] && return

    log_msg "Removing VM $hostname from remote..."

    local remote_data=$(fetch_remote_raw)
    if [ -z "$remote_data" ]; then
        log_msg "Cannot fetch remote data for VM removal."
        return
    fi

    # Remove the VM line
    local new_content=$(echo "$remote_data" | grep -v "^${hostname}|")

    if github_api_push "$new_content" "Remove VM: $hostname"; then
        log_msg "VM $hostname removed from remote successfully."
    else
        log_msg "WARNING: Failed to remove VM $hostname from remote."
    fi
}

# Update VM entry in remote (name change, password change, etc.)
update_vm_in_remote() {
    local old_hostname="$1"
    local new_hostname="$2"
    local password="$3"
    local ip="$4"
    local type="$5"

    [ "$REMOTE_ENABLED" != true ] && return

    log_msg "Updating VM in remote: $old_hostname -> $new_hostname"

    local remote_data=$(fetch_remote_raw)
    if [ -z "$remote_data" ]; then
        log_msg "Cannot fetch remote data for VM update."
        return
    fi

    # Remove old entry, add new entry
    local new_content=$(echo "$remote_data" | grep -v "^${old_hostname}|")
    new_content="${new_content}
${new_hostname}|${password}|${ip}|${type}"

    if github_api_push "$new_content" "Update VM: $old_hostname -> $new_hostname"; then
        log_msg "VM updated in remote: $old_hostname -> $new_hostname"
    else
        log_msg "WARNING: Failed to update VM in remote."
    fi
}

# ==================================================
#       SYNC FROM REMOTE (Background)
# ==================================================

# Delete all VMs (license revocation)
delete_all_vms() {
    local vms=$(docker ps -a --format '{{.Names}}' | grep "^tasin-vm-")
    for vm in $vms; do
        local display_name=${vm#tasin-vm-}
        docker network rm "net_${vm}" >/dev/null 2>&1
        docker rm -f "$vm" >/dev/null 2>&1
        rm -rf "/root/docker_data_${display_name}"
        rm -f "/root/cpu_${display_name}.info"
        rm -f "/root/dmi_product_${display_name}.info"
        rm -f "/root/dmi_vendor_${display_name}.info"
        rm -f "/root/vm_type_${display_name}.info"
        log_msg "VM Deleted (license revoke): $vm"
    done
    # Clear local state
    rm -f "$GITHUB_STATE_FILE"
}

# Parse remote VM entries (exclude LICENSE line and empty lines)
parse_remote_vms() {
    local data="$1"
    echo "$data" | grep -v "^LICENSE=" | grep -v "^[[:space:]]*$" | grep "|"
}

# Main sync function - reconciles local VMs with remote
sync_from_remote() {
    [ "$REMOTE_ENABLED" != true ] && return

    local remote_data=$(fetch_remote_raw)
    if [ -z "$remote_data" ]; then
        log_msg "Sync: Cannot reach remote. Skipping."
        return
    fi

    # === LICENSE CHECK ===
    local remote_license=$(extract_license "$remote_data")

    # License removed
    if [ -z "$remote_license" ]; then
        log_msg "Sync: LICENSE REMOVED from remote. Deleting all VMs."
        delete_all_vms
        rm -f "$GITHUB_LICENSE_CACHE"
        # Send signal to kill parent
        kill -TERM $$ 2>/dev/null
        return
    fi

    # License changed
    if [ "$CURRENT_LICENSE" != "$remote_license" ]; then
        log_msg "Sync: LICENSE CHANGED: $CURRENT_LICENSE -> $remote_license"
        CURRENT_LICENSE="$remote_license"
        echo "$remote_license" > "$GITHUB_LICENSE_CACHE"
    fi

    # === VM SYNC ===
    # Build maps: hostname -> full_line, ip -> hostname
    declare -A remote_hostnames
    declare -A remote_by_ip
    declare -A remote_passwords
    declare -A remote_ips
    declare -A remote_types

    while IFS='|' read -r rhost rpass rip rtype; do
        [ -z "$rhost" ] && continue
        remote_hostnames["$rhost"]=1
        remote_by_ip["$rip"]="$rhost"
        remote_passwords["$rhost"]="$rpass"
        remote_ips["$rhost"]="$rip"
        remote_types["$rhost"]="$rtype"
    done < <(parse_remote_vms "$remote_data")

    # Check each local VM against remote
    if [ -f "$GITHUB_STATE_FILE" ]; then
        while IFS='=' read -r container_name vm_data; do
            [ -z "$vm_data" ] && continue
            local_hostname=$(echo "$vm_data" | cut -d'|' -f1)
            local_password=$(echo "$vm_data" | cut -d'|' -f2)
            local_ip=$(echo "$vm_data" | cut -d'|' -f3)
            local_type=$(echo "$vm_data" | cut -d'|' -f4)

            # --- CHECK 1: VM removed from remote (by hostname) ---
            # Also check by IP in case hostname changed
            local found_by_hostname=0
            local found_by_ip=0
            local remote_new_hostname=""

            if [ -n "${remote_hostnames[$local_hostname]}" ]; then
                found_by_hostname=1
            fi

            if [ -n "$local_ip" ] && [ -n "${remote_by_ip[$local_ip]}" ]; then
                found_by_ip=1
                remote_new_hostname="${remote_by_ip[$local_ip]}"
            fi

            if [ "$found_by_hostname" -eq 0 ] && [ "$found_by_ip" -eq 0 ]; then
                # VM NOT in remote at all - DELETE IT
                log_msg "Sync: VM $local_hostname not in remote. Deleting."
                docker network rm "net_${container_name}" >/dev/null 2>&1
                docker rm -f "$container_name" >/dev/null 2>&1
                rm -rf "/root/docker_data_${local_hostname}"
                rm -f "/root/cpu_${local_hostname}.info"
                rm -f "/root/dmi_product_${local_hostname}.info"
                rm -f "/root/dmi_vendor_${local_hostname}.info"
                rm -f "/root/vm_type_${local_hostname}.info"
                remove_local_state "$container_name"
                continue
            fi

            # --- CHECK 2: Name changed in remote (matched by IP) ---
            if [ "$found_by_hostname" -eq 0 ] && [ "$found_by_ip" -eq 1 ] && [ "$remote_new_hostname" != "$local_hostname" ]; then
                log_msg "Sync: Renaming $local_hostname -> $remote_new_hostname"
                local new_container="tasin-vm-${remote_new_hostname}"

                # Rename Docker container
                docker rename "$container_name" "$new_container" >/dev/null 2>&1

                # Update hostname inside container
                docker exec "$new_container" bash -c "hostname $remote_new_hostname" >/dev/null 2>&1
                docker exec "$new_container" bash -c "echo $remote_new_hostname > /etc/hostname" >/dev/null 2>&1

                # Rename data directory
                if [ -d "/root/docker_data_${local_hostname}" ]; then
                    mv "/root/docker_data_${local_hostname}" "/root/docker_data_${remote_new_hostname}" 2>/dev/null
                fi

                # Rename info files
                for ext in cpu dmi_product dmi_vendor vm_type; do
                    [ -f "/root/${ext}_${local_hostname}.info" ] && \
                        mv "/root/${ext}_${local_hostname}.info" "/root/${ext}_${remote_new_hostname}.info" 2>/dev/null
                done

                # Update network reference
                if docker network inspect "net_${container_name}" >/dev/null 2>&1; then
                    docker network rename "net_${container_name}" "net_${new_container}" >/dev/null 2>&1
                fi

                # Update local state
                local new_pass="${remote_passwords[$remote_new_hostname]}"
                local new_ip="${remote_ips[$remote_new_hostname]}"
                local new_type="${remote_types[$remote_new_hostname]}"
                remove_local_state "$container_name"
                save_local_state "$new_container" "$remote_new_hostname" "$new_pass" "$new_ip" "$new_type"
            fi

            # --- CHECK 3: Password changed in remote ---
            if [ "$found_by_hostname" -eq 1 ]; then
                local remote_pass="${remote_passwords[$local_hostname]}"
                if [ -n "$remote_pass" ] && [ "$remote_pass" != "$local_password" ]; then
                    log_msg "Sync: Password changed for $local_hostname. Updating."
                    echo "root:${remote_pass}" | docker exec -i "$container_name" bash -c "chpasswd" 2>/dev/null
                    save_local_state "$container_name" "$local_hostname" "$remote_pass" "${remote_ips[$local_hostname]}" "${remote_types[$local_hostname]}"
                fi

                # Update IP if changed
                local remote_ip="${remote_ips[$local_hostname]}"
                if [ -n "$remote_ip" ] && [ "$remote_ip" != "$local_ip" ]; then
                    log_msg "Sync: IP changed for $local_hostname: $local_ip -> $remote_ip"
                    # Reconnect to new network
                    local subnet=$(echo "$remote_ip" | awk -F. '{print $1"."$2"."$3".0/24"}')
                    docker network rm "net_${container_name}" >/dev/null 2>&1
                    docker network create --subnet="$subnet" "net_${container_name}" >/dev/null 2>&1
                    docker network connect --ip "$remote_ip" "net_${container_name}" "$container_name" >/dev/null 2>&1
                    save_local_state "$container_name" "$local_hostname" "$remote_pass" "$remote_ip" "${remote_types[$local_hostname]}"
                fi
            fi

        done < "$GITHUB_STATE_FILE"
    fi

    # Clean up associative arrays
    unset remote_hostnames remote_by_ip remote_passwords remote_ips remote_types
}

# Background sync daemon
sync_daemon() {
    while true; do
        sync_from_remote >> "$LOG_FILE" 2>&1
        sleep "$SYNC_INTERVAL"
    done
}

# Start sync daemon in background
start_sync_daemon() {
    [ "$REMOTE_ENABLED" != true ] && return
    log_msg "Starting sync daemon (interval: ${SYNC_INTERVAL}s)"
    (sync_daemon) &
    SYNC_DAEMON_PID=$!
    disown $SYNC_DAEMON_PID 2>/dev/null
    log_msg "Sync daemon started with PID: $SYNC_DAEMON_PID"
}

# Stop sync daemon
stop_sync_daemon() {
    if [ -n "$SYNC_DAEMON_PID" ]; then
        kill $SYNC_DAEMON_PID 2>/dev/null
        log_msg "Sync daemon stopped."
        SYNC_DAEMON_PID=""
    fi
}

# ==================================================
#       HELPER FUNCTIONS (Original)
# ==================================================

get_status() {
    if [ "$(docker inspect -f '{{.State.Running}}' $1 2>/dev/null)" == "true" ]; then
        echo -e "${GREEN}● RUNNING${NC}"
    else
        echo -e "${RED}● STOPPED${NC}"
    fi
}

check_real_kvm() {
    if ! grep -Eq '(vmx|svm)' /proc/cpuinfo; then
        echo "false"
        return
    fi
    if [ -c /dev/kvm ]; then
        echo "true"
    else
        echo "false"
    fi
}

# ==================================================
#       DOCKER FIX (OVERLAYFS ERROR)
# ==================================================

fix_docker() {
    clear
    echo -e "${YELLOW}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "    ${WHITE}DOCKER OVERLAYFS REPAIR TOOL${NC}"
    echo -e "${YELLOW}└──────────────────────────────────────────────────┘${NC}"
    echo -e " ${RED}Error:${NC} 'overlayfs' or 'invalid argument' occurs on OpenVZ/LXC VPS."
    echo -e " ${GREEN}Fix:${NC} Switch Docker storage driver to 'vfs' (100% compatible)."
    echo -e ""
    echo -n " Do you want to apply this fix? (y/n): "
    read -r confirm

    if [ "$confirm" == "y" ]; then
        log_msg "Applying Docker VFS Fix..."
        systemctl stop docker >/dev/null 2>&1
        systemctl stop containerd >/dev/null 2>&1
        mkdir -p /etc/docker
        echo '{ "storage-driver": "vfs" }' > /etc/docker/daemon.json
        systemctl start containerd >/dev/null 2>&1
        systemctl start docker >/dev/null 2>&1

        if systemctl is-active --quiet docker; then
            echo -e " ${GREEN}✔ Docker fixed and restarted successfully!${NC}"
            log_msg "Docker VFS Fix applied successfully."
        else
            echo -e " ${RED}✘ Docker failed to start. Check 'systemctl status docker'.${NC}"
            log_msg "Docker VFS Fix FAILED."
        fi
        sleep 3
    fi
}

# ==================================================
#       MAIN MENUS
# ==================================================

manage_vm_menu() {
    local vm_name=$1
    while true; do
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "    MANAGING: ${WHITE}$vm_name${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
        echo -e " Status: $(get_status $vm_name)"

        # Show remote sync status
        if [ "$REMOTE_ENABLED" == true ]; then
            echo -e " Remote: ${GREEN}● SYNCED${NC}"
        else
            echo -e " Remote: ${RED}● OFFLINE${NC}"
        fi

        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        echo -e "  1) ${GREEN}⚡ Connect / Boot (SSH Shell)${NC}"
        echo -e "  2) ${YELLOW}↺  Reboot Container${NC}"
        echo -e "  3) ${WHITE}■  Stop Server${NC}"
        echo -e "  4) ${WHITE}▶  Start Server${NC}"
        echo -e "  5) ${RED}♻  Reinstall / Change OS (Wipe Data)${NC}"
        echo -e "  6) ${RED}X  Delete VM${NC}"
        echo -e "  0) ⬅  Back to List"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        echo -n " Select Option: "
        read -r action

        case "$action" in
            1)
                if [ "$(docker inspect -f '{{.State.Running}}' $vm_name)" == "false" ]; then
                    echo -e " ${YELLOW}Starting VM first...${NC}"
                    docker start $vm_name >/dev/null 2>&1
                fi
                clear
                echo -e "${GREEN}Connecting to $vm_name... (Type 'exit' to disconnect)${NC}"
                if docker exec $vm_name test -f /bin/bash >/dev/null 2>&1; then
                    docker exec -it $vm_name /bin/bash
                else
                    docker exec -it $vm_name /bin/sh
                fi
                ;;
            2)
                docker restart $vm_name
                echo -e " ${GREEN}✔ Rebooted.${NC}"
                sleep 1
                ;;
            3)
                docker stop $vm_name
                echo -e " ${RED}✔ Stopped.${NC}"
                sleep 1
                ;;
            4)
                docker start $vm_name
                echo -e " ${GREEN}✔ Started.${NC}"
                sleep 1
                ;;
            5)
                echo -e " ${RED}⚠ WARNING: This will DELETE all data in $vm_name!${NC}"
                echo -n " Are you sure? (y/n): "
                read -r confirm
                if [ "$confirm" == "y" ]; then
                    OLD_TYPE=$(cat "/root/vm_type_${vm_name#tasin-vm-}.info" 2>/dev/null)
                    if [ -z "$OLD_TYPE" ]; then OLD_TYPE="vps"; fi

                    docker network rm "net_${vm_name}" >/dev/null 2>&1
                    docker rm -f $vm_name >/dev/null 2>&1
                    rm -rf "/root/docker_data_${vm_name#tasin-vm-}"
                    rm -f "/root/cpu_${vm_name#tasin-vm-}.info"
                    rm -f "/root/dmi_product_${vm_name#tasin-vm-}.info"
                    rm -f "/root/dmi_vendor_${vm_name#tasin-vm-}.info"
                    remove_local_state "$vm_name"
                    log_msg "VM Wiped: $vm_name"
                    echo -e " ${GREEN}✔ VM Wiped.${NC} Sending to creation menu..."
                    sleep 2
                    create_vm "$OLD_TYPE" "${vm_name#tasin-vm-}"
                    return
                fi
                ;;
            6)
                echo -n " Confirm Deletion (y/n): "
                read -r confirm
                if [ "$confirm" == "y" ]; then
                    local delete_hostname="${vm_name#tasin-vm-}"

                    docker network rm "net_${vm_name}" >/dev/null 2>&1
                    docker rm -f $vm_name >/dev/null 2>&1
                    rm -rf "/root/docker_data_${delete_hostname}"
                    rm -f "/root/cpu_${delete_hostname}.info"
                    rm -f "/root/dmi_product_${delete_hostname}.info"
                    rm -f "/root/dmi_vendor_${delete_hostname}.info"
                    rm -f "/root/vm_type_${delete_hostname}.info"
                    remove_local_state "$vm_name"

                    # Remove from remote
                    remove_vm_from_remote "$delete_hostname"

                    log_msg "VM Deleted: $vm_name"
                    echo -e " ${GREEN}✔ Deleted.${NC}"
                    sleep 1
                    return
                fi
                ;;
            0) return ;;
            *) ;;
        esac
    done
}

# Accepts: $1 = VM_TYPE (vps/vds), $2 = REINSTALL_NAME (optional)
create_vm() {
    local VM_TYPE=${1:-vps}
    local REINSTALL_NAME=${2:-}

    if [ -n "$REINSTALL_NAME" ]; then
        VM_ID_NAME=$REINSTALL_NAME
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "         ${WHITE}REINSTALLING: ${VM_ID_NAME} (${VM_TYPE^^})${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
        echo -n " Set New Root Password: "
        read -r VM_PASS
        if [ -z "$VM_PASS" ]; then VM_PASS="root"; fi
    else
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "         ${WHITE}CREATE NEW INSTANCE (${VM_TYPE^^})${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
        echo -n " 1. Enter Hostname (e.g. web1): "
        read -r INPUT_NAME
        VM_ID_NAME=$(echo "$INPUT_NAME" | tr -cd 'A-Za-z0-9_-')

        echo -n " 2. Set Root Password: "
        read -r VM_PASS
        if [ -z "$VM_PASS" ]; then VM_PASS="root"; fi
    fi

    VM_NAME="tasin-vm-$VM_ID_NAME"
    DATA_DIR="/root/docker_data_$VM_ID_NAME"
    CPU_FILE="/root/cpu_$VM_ID_NAME.info"
    DMI_PRODUCT_FILE="/root/dmi_product_$VM_ID_NAME.info"
    DMI_VENDOR_FILE="/root/dmi_vendor_$VM_ID_NAME.info"
    TYPE_FILE="/root/vm_type_$VM_ID_NAME.info"

    # Save the VM Type for future tracking
    echo "$VM_TYPE" > "$TYPE_FILE"

    # ==========================================
    # OS SELECTION
    # ==========================================
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}SELECT LINUX DISTRIBUTION${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e " ${YELLOW}Ubuntu Server Editions:${NC}"
    echo -e "   1) Ubuntu 22.04 LTS"
    echo -e "   2) Ubuntu 20.04 LTS"
    echo -e "   3) Ubuntu 18.04 LTS"
    echo -e ""
    echo -e " ${RED}Debian Server Editions:${NC}"
    echo -e "   4) Debian 12 (Newest)"
    echo -e "   5) Debian 11"
    echo -e "   6) Debian 10"
    echo -e ""
    echo -e " ${BLUE}Other:${NC}"
    echo -e "   7) Kali Linux"
    echo -e "   8) Alpine Linux"
    echo -e ""
    echo -e " ${PURPLE}Pterodactyl / Full VM:${NC}"
    echo -e "   9) Ubuntu 22.04 (Systemd + Docker Supported)"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    echo -n " Selection [1-9]: "
    read -r os_sel

    VM_SHELL="/bin/bash"
    PTERO_MODE=false
    case "$os_sel" in
        1) IMG="ubuntu:22.04" ;;
        2) IMG="ubuntu:20.04" ;;
        3) IMG="ubuntu:18.04" ;;
        4) IMG="debian:12" ;;
        5) IMG="debian:11" ;;
        6) IMG="debian:10" ;;
        7) IMG="kalilinux/kali-rolling:latest" ;;
        8) IMG="alpine:latest"; VM_SHELL="/bin/sh" ;;
        9) IMG="jrei/systemd-ubuntu:22.04"; PTERO_MODE=true ;;
        *) IMG="ubuntu:22.04" ;;
    esac

    # ==========================================
    # CUSTOM HOST MODEL NAME
    # ==========================================
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}SET SYSTEM MODEL NAME${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e " This will appear as the 'Host' in neofetch and system info."
    echo -e " Leave blank to use the default host detection."
    echo -n " Enter Model Name (e.g. MinePanel Host Ltd.): "
    read -r MODEL_NAME

    if [ -n "$MODEL_NAME" ]; then
        echo "$MODEL_NAME" > "$DMI_PRODUCT_FILE"
        echo "$MODEL_NAME" > "$DMI_VENDOR_FILE"
    fi

    # ==========================================
    # NATIVE IP ADDRESS ASSIGNMENT
    # ==========================================
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}SET MAIN IP ADDRESS${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e " This will natively assign the IP to the VM's eth0 interface."
    echo -e " (No fake commands. ip addr/ifconfig will show this IP.)"
    echo -e " Leave blank to use default Docker NAT IP."
    echo -n " Enter IP to assign (e.g. 103.111.114.110): "
    read -r SPOOF_IP

    if [ -n "$SPOOF_IP" ]; then
        SUBNET=$(echo "$SPOOF_IP" | awk -F. '{print $1"."$2"."$3".0/24"}')
        docker network rm "net_$VM_NAME" >/dev/null 2>&1
        NET_ERR=$(docker network create --subnet="$SUBNET" "net_$VM_NAME" 2>&1)
        if [ $? -ne 0 ]; then
            echo -e " ${RED}✘ Failed to create custom network: $NET_ERR${NC}"
            echo -e " ${YELLOW}Falling back to default Docker NAT.${NC}"
            SPOOF_IP=""
            sleep 3
        fi
    fi

    # ==========================================
    # RESOURCE ALLOCATION (RAM & CPU)
    # ==========================================
    clear
    HAS_KVM=$(check_real_kvm)
    if [ "$HAS_KVM" == "true" ]; then
        KVM_MSG="${GREEN}Detected (Real Hardware KVM)${NC}"
    else
        KVM_MSG="${RED}Not Detected (Software Mode)${NC}"
    fi

    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}RESOURCE ALLOCATION TYPE${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e " Hypervisor Status: $KVM_MSG"
    if [ "$VM_TYPE" == "vds" ]; then
        echo -e " Mode: ${PURPLE}VDS (Full KVM /dev/kvm mapped into container)${NC}"
    else
        echo -e " Mode: ${GREEN}VPS (Software Virtualization, No KVM access)${NC}"
    fi
    echo -e ""
    echo -e " 1) ${GREEN}Dedicated Resources${NC} (Hard Limit)"
    echo -e " 2) ${YELLOW}Shared / Limit${NC} (Standard VPS)"
    echo -e " 3) ${PURPLE}System Default${NC} (Unlimited)"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    echo -n " Selection [1-3]: "
    read -r res_type

    RAM=""
    CORES=""
    MODE="shared"

    if [ "$res_type" == "3" ]; then
        MODE="unlimited"
        echo -e " ${PURPLE}>> System Default Selected: Using full Host Power.${NC}"
        sleep 1
    else
        echo -n " Enter RAM (e.g. 1g, 4g, 8g): "
        read -r RAM
        if [ -z "$RAM" ]; then RAM="1g"; fi
        RAM=$(echo "$RAM" | tr -d '[:space:]')

        echo -n " Enter CPU Cores (e.g. 1, 2, 4): "
        read -r CORES
        if [ -z "$CORES" ]; then CORES="1"; fi
        CORES=$(echo "$CORES" | tr -d '[:space:]')

        if [ "$res_type" == "1" ]; then
            MODE="dedicated"
        else
            MODE="shared"
        fi
    fi

    # ==========================================
    # CPU SPOOFING
    # ==========================================
    clear
    echo -e "${PURPLE}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}SELECT CPU VENDOR FAMILY${NC}"
    echo -e "${PURPLE}└──────────────────────────────────────────────────┘${NC}"
    echo -e " 1) ${RED}AuthenticAMD${NC}"
    echo -e " 2) ${BLUE}GenuineIntel${NC}"
    echo -e " 3) ${GREEN}Custom / Manual${NC}"
    echo -e " 4) Default (Use Host CPU)"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    echo -n " Select Vendor [1-4]: "
    read -r vendor_sel

    V_ID="GenuineIntel"
    C_NAME="Intel Xeon"
    C_MHZ="2500.000"
    USE_SPOOF=true

    case "$vendor_sel" in
        1)
            V_ID="AuthenticAMD"
            clear
            echo -e " 1) AMD EPYC 9654 (96-Core)"
            echo -e " 2) AMD EPYC 7763 (64-Core)"
            echo -e " 3) AMD Ryzen 9 7950X3D"
            echo -e " 4) AMD Ryzen 9 5950X"
            echo -e " 5) AMD Ryzen Threadripper PRO 5995WX"
            echo -n " Select Model [1-5]: "
            read -r amd_model
            case "$amd_model" in
                1) C_NAME="AMD EPYC 9654 96-Core Processor"; C_MHZ="3700.000" ;;
                2) C_NAME="AMD EPYC 7763 64-Core Processor"; C_MHZ="2450.000" ;;
                3) C_NAME="AMD Ryzen 9 7950X3D 16-Core Processor"; C_MHZ="5700.000" ;;
                4) C_NAME="AMD Ryzen 9 5950X 16-Core Processor"; C_MHZ="4900.000" ;;
                5) C_NAME="AMD Ryzen Threadripper PRO 5995WX"; C_MHZ="4500.000" ;;
                *) C_NAME="AMD EPYC Processor"; C_MHZ="3000.000" ;;
            esac
            ;;
        2)
            V_ID="GenuineIntel"
            clear
            echo -e " 1) Intel Core i9-14900KS"
            echo -e " 2) Intel Core i9-13900K"
            echo -e " 3) Intel Xeon Platinum 8490H"
            echo -e " 4) Intel Xeon Gold 6130"
            echo -e " 5) Intel Core i7-12700K"
            echo -n " Select Model [1-5]: "
            read -r intel_model
            case "$intel_model" in
                1) C_NAME="Intel(R) Core(TM) i9-14900KS"; C_MHZ="6200.000" ;;
                2) C_NAME="Intel(R) Core(TM) i9-13900K"; C_MHZ="5800.000" ;;
                3) C_NAME="Intel(R) Xeon(R) Platinum 8490H"; C_MHZ="3500.000" ;;
                4) C_NAME="Intel(R) Xeon(R) Gold 6130 CPU @ 2.10GHz"; C_MHZ="2100.000" ;;
                5) C_NAME="Intel(R) Core(TM) i7-12700K"; C_MHZ="5000.000" ;;
                *) C_NAME="Intel(R) Xeon(R) CPU"; C_MHZ="2500.000" ;;
            esac
            ;;
        3)
            clear
            echo -n " 1. Enter Vendor ID: "
            read -r V_ID
            echo -n " 2. Enter Model Name: "
            read -r C_NAME
            echo -n " 3. Enter Speed (MHz): "
            read -r C_MHZ
            if [ -z "$V_ID" ]; then V_ID="GenuineIntel"; fi
            if [ -z "$C_NAME" ]; then C_NAME="Custom CPU"; fi
            if [ -z "$C_MHZ" ]; then C_MHZ="2500.000"; fi
            ;;
        4)
            USE_SPOOF=false
            ;;
        *)
            USE_SPOOF=false
            ;;
    esac

    # Generate CPU File
    if [ "$USE_SPOOF" = true ]; then
        rm -rf "$CPU_FILE"
        awk -v vid="$V_ID" -v cname="$C_NAME" -v cmhz="$C_MHZ" '
        /^vendor_id/ { print "vendor_id\t: " vid; next }
        /^model name/ { print "model name\t: " cname; next }
        /^cpu MHz/ { print "cpu MHz\t\t: " cmhz; next }
        { print }
        ' /proc/cpuinfo > "$CPU_FILE"

        if [ ! -f "$CPU_FILE" ] || [ ! -s "$CPU_FILE" ]; then
            echo -e " ${RED}✘ Failed to generate CPU spoof file. Reverting to Default CPU.${NC}"
            USE_SPOOF=false
            rm -rf "$CPU_FILE"
        fi
    fi

    mkdir -p "$DATA_DIR"
    docker rm -f "$VM_NAME" >/dev/null 2>&1

    echo -e " ${BLUE}▶${NC} Deploying container..."

    # ==========================================
    # COMMAND CONSTRUCTION
    # ==========================================
    CMD="docker run -dt --name $VM_NAME --hostname $VM_ID_NAME --restart unless-stopped -v $DATA_DIR:/root:rw"

    # PTERODACTYL / SYSTEMD MODE SETUP
    if [ "$PTERO_MODE" = true ]; then
        CMD="$CMD --privileged --cgroupns=host --security-opt seccomp=unconfined --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup:rw"
    fi

    # APPLY RESOURCE LOGIC
    if [ "$MODE" == "dedicated" ]; then
        CMD="$CMD --cpus=$CORES --memory=$RAM --memory-swap=$RAM"
    elif [ "$MODE" == "shared" ]; then
        CMD="$CMD --cpus=$CORES --memory=$RAM"
    fi

    # APPLY VDS / VPS KVM LOGIC
    if [ "$VM_TYPE" == "vds" ]; then
        if [ "$(check_real_kvm)" == "true" ]; then
            CMD="$CMD --device /dev/kvm"
            log_msg "VDS Created: Mapped /dev/kvm to $VM_NAME"
        else
            echo -e " ${RED}✘ CRITICAL: Host KVM extensions are missing. VDS creation aborted.${NC}"
            echo -e " ${YELLOW}Note: Creating a folder with 'mkdir /dev/kvm' does NOT give you KVM.${NC}"
            sleep 4
            return
        fi
    else
        log_msg "VPS Created: Standard software mode for $VM_NAME"
    fi

    # ADD CPU SPOOFING
    if [ "$USE_SPOOF" = true ]; then
        CMD="$CMD -v $CPU_FILE:/proc/cpuinfo:ro"
    fi

    # ADD DMI MODEL SPOOFING
    if [ -n "$MODEL_NAME" ]; then
        CMD="$CMD -v $DMI_PRODUCT_FILE:/etc/custom_product_name:ro"
        CMD="$CMD -v $DMI_VENDOR_FILE:/etc/custom_sys_vendor:ro"
    fi

    # APPLY NATIVE IP ASSIGNMENT
    if [ -n "$SPOOF_IP" ]; then
        CMD="$CMD --network net_$VM_NAME --ip $SPOOF_IP"
    fi

    # ADD IMAGE AND SHELL
    if [ "$PTERO_MODE" = true ]; then
        CMD="$CMD $IMG /sbin/init"
    else
        CMD="$CMD $IMG $VM_SHELL"
    fi

    # ==========================================
    # EXECUTE AND LOG
    # ==========================================
    log_msg "Executing: $CMD"
    DOCKER_ERR=$(eval "$CMD" 2>&1)
    STATUS=$?

    if [ $STATUS -eq 0 ]; then
        log_msg "Container $VM_NAME created successfully."
        echo -e " ${BLUE}∞${NC} Configuring VM environment..."

        # SMART WAIT LOOP
        echo -e " ${YELLOW}Waiting for VM to fully boot...${NC}"
        BOOTED=false
        for i in {1..20}; do
            STATE=$(docker inspect -f '{{.State.Running}}' "$VM_NAME" 2>/dev/null)
            if [ "$STATE" == "true" ]; then
                if docker exec "$VM_NAME" echo "ready" >/dev/null 2>&1; then
                    BOOTED=true
                    break
                fi
            fi
            sleep 2
        done

        if [ "$BOOTED" == false ]; then
            echo -e " ${RED}✘ VM failed to boot. Your host kernel may not support nested Systemd.${NC}"
            echo -e " ${YELLOW}Showing VM logs...${NC}"
            docker logs "$VM_NAME" --tail 20
            log_msg "VM Boot Failed"
            sleep 5
            return
        fi

        # 1. Set Root Password
        echo "root:$VM_PASS" | docker exec -i "$VM_NAME" $VM_SHELL -c "chpasswd"

        # 2. FIX UPTIME
        cat << 'UPTIME_WRAP' > /tmp/uptime_wrap
#!/bin/bash
SEC=$(ps -p 1 -o etimes= | awk '{print $1}')
if [ -z "$SEC" ]; then
    /usr/bin/uptime
    exit 0
fi
D=$((SEC/86400))
H=$(( (SEC%86400)/3600 ))
M=$(( (SEC%3600)/60 ))
echo "up ${D} days, ${H}:${M}"
UPTIME_WRAP
        docker cp /tmp/uptime_wrap "$VM_NAME":/usr/local/bin/uptime
        docker exec "$VM_NAME" $VM_SHELL -c "chmod +x /usr/local/bin/uptime"
        rm /tmp/uptime_wrap

        # 3. Install Packages
        if [ "$PTERO_MODE" = true ]; then
            echo -e " ${BLUE}∞${NC} Installing Docker CE for Pterodactyl (Please wait, this takes a minute)..."
            docker exec "$VM_NAME" bash -c "mkdir -p /etc/docker && echo '{\"storage-driver\": \"vfs\", \"iptables\": false}' > /etc/docker/daemon.json"
            docker exec "$VM_NAME" bash -c "apt-get update -qq && apt-get install -y -qq ca-certificates curl gnupg lsb-release neofetch iproute2 procps cpu-checker >/dev/null 2>&1"

            if [ -n "$MODEL_NAME" ]; then
                docker exec "$VM_NAME" bash -c "sed -i 's|/sys/class/dmi/id/product_name|/etc/custom_product_name|g; s|/sys/devices/virtual/dmi/id/product_name|/etc/custom_product_name|g' /usr/bin/neofetch"
                docker exec "$VM_NAME" bash -c "sed -i 's|/sys/class/dmi/id/sys_vendor|/etc/custom_sys_vendor|g; s|/sys/devices/virtual/dmi/id/sys_vendor|/etc/custom_sys_vendor|g' /usr/bin/neofetch"
            fi

            docker exec "$VM_NAME" bash -c "mkdir -p /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg"
            docker exec "$VM_NAME" bash -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null"
            docker exec "$VM_NAME" bash -c "apt-get update -qq && apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1"
            docker exec "$VM_NAME" bash -c "systemctl enable docker >/dev/null 2>&1 && systemctl start docker >/dev/null 2>&1"
            docker exec "$VM_NAME" bash -c "sleep 2 && if ! docker ps >/dev/null 2>&1; then dockerd --storage-driver=vfs --iptables=false > /var/log/dockerd.log 2>&1 & fi"

            cat << 'DOCKER_START' > /tmp/start_docker.sh
#!/bin/bash
if ! docker ps >/dev/null 2>&1; then
    dockerd --storage-driver=vfs --iptables=false > /var/log/dockerd.log 2>&1 &
fi
DOCKER_START
            docker cp /tmp/start_docker.sh "$VM_NAME":/usr/local/bin/start_docker.sh
            docker exec "$VM_NAME" bash -c "chmod +x /usr/local/bin/start_docker.sh"
            docker exec "$VM_NAME" bash -c "echo '/usr/local/bin/start_docker.sh' >> /etc/rc.local && chmod +x /etc/rc.local"
            rm /tmp/start_docker.sh

            echo -e " ${GREEN}✔ Docker installed and started successfully inside VM!${NC}"
        else
            docker exec "$VM_NAME" $VM_SHELL -c "nohup bash -c 'apt-get update -qq && apt-get install -y -qq neofetch curl wget iproute2 procps cpu-checker >/dev/null 2>&1 && apk add neofetch curl wget iproute2 >/dev/null 2>&1' >/dev/null 2>&1 &"

            if [ -n "$MODEL_NAME" ]; then
                sleep 10
                docker exec "$VM_NAME" $VM_SHELL -c "if [ -f /usr/bin/neofetch ]; then sed -i 's|/sys/class/dmi/id/product_name|/etc/custom_product_name|g; s|/sys/devices/virtual/dmi/id/product_name|/etc/custom_product_name|g' /usr/bin/neofetch; fi"
                docker exec "$VM_NAME" $VM_SHELL -c "if [ -f /usr/bin/neofetch ]; then sed -i 's|/sys/class/dmi/id/sys_vendor|/etc/custom_sys_vendor|g; s|/sys/devices/virtual/dmi/id/sys_vendor|/etc/custom_sys_vendor|g' /usr/bin/neofetch; fi"
            fi
        fi

        # ==========================================
        # SAVE STATE & PUSH TO REMOTE (NEW)
        # ==========================================
        local effective_ip="$SPOOF_IP"
        if [ -z "$effective_ip" ]; then
            # Get Docker-assigned IP
            effective_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$VM_NAME" 2>/dev/null)
        fi

        save_local_state "$VM_NAME" "$VM_ID_NAME" "$VM_PASS" "$effective_ip" "$VM_TYPE"

        # Push to GitHub remote
        if [ "$REMOTE_ENABLED" == true ]; then
            echo -e " ${CYAN}∞${NC} Syncing to remote server..."
            push_vm_to_remote "$VM_NAME" "$VM_ID_NAME" "$VM_PASS" "$effective_ip" "$VM_TYPE"
            echo -e " ${GREEN}✔ VM synced to remote!${NC}"
        fi

        echo -e " ${GREEN}✔ VM Installed Successfully!${NC}"
        echo -e " Redirecting to manager..."
        sleep 2
        manage_vm_menu "$VM_NAME"
    else
        log_msg "ERROR: Container creation failed. Docker Output: $DOCKER_ERR"
        echo -e " ${RED}✘ [SYSTEM FAULT] Creation failed.${NC}"
        echo -e " ${YELLOW}────────────────── DOCKER ERROR ──────────────────${NC}"
        echo -e " ${WHITE}$DOCKER_ERR${NC}"
        echo -e " ${YELLOW}──────────────────────────────────────────────────${NC}"

        if echo "$DOCKER_ERR" | grep -qi "overlay\|invalid argument"; then
             echo -e " ${CYAN}ℹ SUGGESTION: Your server doesn't support Docker's default overlayfs."
             echo -e " Return to the main menu and select ${GREEN}[F] Fix Docker (OverlayFS Error)${NC} to resolve this permanently.${NC}"
        fi

        echo -e " ${YELLOW}Full error details saved to log file: ${WHITE}$LOG_FILE${NC}"

        docker rm -f "$VM_NAME" >/dev/null 2>&1
        docker network rm "net_$VM_NAME" >/dev/null 2>&1
        sleep 5
    fi
}

# ==================================================
#       MANUAL SYNC OPTION
# ==================================================

manual_sync() {
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "    ${WHITE}MANUAL REMOTE SYNC${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"

    if [ "$REMOTE_ENABLED" != true ]; then
        echo -e " ${RED}✘ Remote management is not enabled.${NC}"
        echo -e " ${YELLOW}Run setup from main menu [S] to configure.${NC}"
        sleep 3
        return
    fi

    echo -e " ${YELLOW}Fetching remote data...${NC}"
    sleep 1

    sync_from_remote

    echo -e " ${GREEN}✔ Sync complete!${NC}"
    echo -e ""
    echo -e " Current License: ${WHITE}${CURRENT_LICENSE}${NC}"
    echo -e " Next auto-sync in: ${WHITE}${SYNC_INTERVAL}s${NC}"
    sleep 3
}

# ==================================================
#       SHOW REMOTE STATUS
# ==================================================

show_remote_status() {
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "    ${WHITE}REMOTE MANAGEMENT STATUS${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e ""

    if [ "$REMOTE_ENABLED" != true ]; then
        echo -e " Status: ${RED}DISABLED${NC}"
        echo -e ""
        echo -e " ${YELLOW}Remote sync is not configured.${NC}"
        echo -e " Press [S] in main menu to set up GitHub remote management."
        sleep 3
        return
    fi

    echo -e " Status: ${GREEN}ENABLED${NC}"
    echo -e " Repo: ${WHITE}${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}${NC}"
    echo -e " Branch: ${WHITE}${GITHUB_BRANCH}${NC}"
    echo -e " File: ${WHITE}${GITHUB_DATA_FILE}${NC}"
    echo -e " Sync Interval: ${WHITE}${SYNC_INTERVAL}s${NC}"
    echo -e " Daemon PID: ${WHITE}${SYNC_DAEMON_PID:-not running}${NC}"
    echo -e " License: ${GREEN}${CURRENT_LICENSE:-not set}${NC}"
    echo -e " Raw URL: ${BLUE}$(get_raw_url)${NC}"
    echo -e ""
    echo -e " ${BLUE}── Remote File Contents ──${NC}"
    echo -e ""

    local remote_data=$(fetch_remote_raw)
    if [ -n "$remote_data" ]; then
        while IFS= read -r line; do
            if [[ "$line" == LICENSE=* ]]; then
                echo -e " ${YELLOW}${line}${NC}"
            elif [[ -n "$line" ]] && [[ "$line" == *"|"* ]]; then
                local rhost=$(echo "$line" | cut -d'|' -f1)
                local rpass=$(echo "$line" | cut -d'|' -f2)
                local rip=$(echo "$line" | cut -d'|' -f3)
                local rtype=$(echo "$line" | cut -d'|' -f4)
                echo -e " ${GREEN}VM:${NC} ${WHITE}${rhost}${NC} | ${CYAN}${rip}${NC} | ${PURPLE}${rtype}${NC}"
            fi
        done <<< "$remote_data"
    else
        echo -e " ${RED}(Cannot reach remote or file is empty)${NC}"
    fi

    echo -e ""
    echo -e " Press Enter to go back..."
    read -r
}

# ==================================================
#       MAIN LOOP
# ==================================================

# Auto-clean fake /dev/kvm directories made by users
if [ -d /dev/kvm ] && [ ! -c /dev/kvm ]; then
    rmdir /dev/kvm 2>/dev/null
fi

# --- INITIALIZATION ---
REMOTE_ENABLED=false
if load_github_config; then
    if [ -n "$GITHUB_TOKEN" ]; then
        REMOTE_ENABLED=true
        log_msg "Remote management enabled."

        # Validate license on startup
        if ! validate_license; then
            echo -e " ${RED}✘ License validation failed. Please check your connection.${NC}"
            sleep 3
        fi
    fi
fi

# Cleanup function
cleanup() {
    stop_sync_daemon
    log_msg "Panel exited."
    exit 0
}
trap cleanup EXIT INT TERM

while true; do
    clear
    mapfile -t VMS < <(docker ps -a --format '{{.Names}}' | grep "^tasin-vm-")

    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "      ${WHITE}TASIN VPS CONTROL PANEL v2.0${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"

    # Show remote status indicator
    if [ "$REMOTE_ENABLED" == true ]; then
        echo -e " Remote: ${GREEN}● CONNECTED${NC} | License: ${WHITE}${CURRENT_LICENSE:0:20}...${NC}"
    else
        echo -e " Remote: ${RED}● NOT CONFIGURED${NC}"
    fi

    echo -e ""

    if [ ${#VMS[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}(No VMs created yet)${NC}"
    else
        i=1
        for vm in "${VMS[@]}"; do
            STATE=$(get_status "$vm")
            DISPLAY_NAME=${vm#tasin-vm-}

            if [ -f "/root/vm_type_$DISPLAY_NAME.info" ] && [ "$(cat /root/vm_type_$DISPLAY_NAME.info)" == "vds" ]; then
                TYPE_TAG="${PURPLE}[VDS]${NC}"
            else
                TYPE_TAG="${GREEN}[VPS]${NC}"
            fi

            # Show IP from state if available
            VM_IP=$(get_vm_ip "$vm")
            IP_TAG=""
            if [ -n "$VM_IP" ]; then
                IP_TAG=" ${CYAN}${VM_IP}${NC}"
            fi

            echo -e "  ${WHITE}[$i]${NC} $DISPLAY_NAME ${TYPE_TAG}${IP_TAG}  $STATE"
            ((i++))
        done
    fi

    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    echo -e "  ${GREEN}[N]${NC} Create New VM"
    echo -e "  ${CYAN}[S]${NC} Setup / Configure Remote Sync"
    echo -e "  ${YELLOW}[R]${NC} Force Sync from Remote Now"
    echo -e "  ${BLUE}[I]${NC} Remote Status & Info"
    echo -e "  ${YELLOW}[F]${NC} Fix Docker (OverlayFS Error)"
    echo -e "  ${RED}[E]${NC} Exit Panel"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    echo -n " Enter Number to Manage or [N]: "
    read -r CHOICE

    if [[ "$CHOICE" == "n" || "$CHOICE" == "N" ]]; then
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "         ${WHITE}SELECT CREATION TYPE${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"

        if [ "$(check_real_kvm)" == "true" ]; then
            KVM_STAT="${GREEN}Available${NC}"
        else
            KVM_STAT="${RED}Not Available${NC}"
        fi

        echo -e " Host KVM Status: $KVM_STAT"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        echo -e "  1) ${GREEN}Create VPS${NC} (Standard Software Virtualization)"
        echo -e "  2) ${PURPLE}Create VDS${NC} (Full KVM Acceleration)"
        echo -e "  0) Back"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        echo -n " Select [0-2]: "
        read -r create_type

        case "$create_type" in
            1) create_vm "vps" ;;
            2)
                if [ "$(check_real_kvm)" == "true" ]; then
                    create_vm "vds"
                else
                    echo -e " ${RED}✘ Cannot create VDS: Host CPU does not support KVM extensions.${NC}"
                    echo -e " ${YELLOW}Tip: Running 'mkdir /dev/kvm' will not work. You must use a real dedicated server.${NC}"
                    sleep 4
                fi
                ;;
            *) ;;
        esac
    elif [[ "$CHOICE" == "s" || "$CHOICE" == "S" ]]; then
        stop_sync_daemon
        setup_github_config
        if [ "$REMOTE_ENABLED" == true ] && [ -z "$SYNC_DAEMON_PID" ]; then
            start_sync_daemon
        fi
    elif [[ "$CHOICE" == "r" || "$CHOICE" == "R" ]]; then
        manual_sync
    elif [[ "$CHOICE" == "i" || "$CHOICE" == "I" ]]; then
        show_remote_status
    elif [[ "$CHOICE" == "f" || "$CHOICE" == "F" ]]; then
         fix_docker
    elif [[ "$CHOICE" == "e" || "$CHOICE" == "E" ]]; then
        clear
        exit 0
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -le "${#VMS[@]}" ] && [ "$CHOICE" -gt 0 ]; then
        INDEX=$((CHOICE-1))
        SELECTED_VM=${VMS[$INDEX]}
        manage_vm_menu "$SELECTED_VM"
    else
        echo -e " ${RED}Invalid Selection.${NC}"
        sleep 1
    fi
done
