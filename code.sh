#!/bin/bash

# =====================================================
#  TASIN VPS CONTROL PANEL v3.0 PREMIUM++
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
DIM='\033[2m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
ORANGE='\033[38;5;208m'
PINK='\033[38;5;213m'
LIME='\033[38;5;154m'
GOLD='\033[38;5;220m'
AMBER='\033[38;5;178m'
BRIGHT_ORANGE='\033[1;38;5;214m'
PREMIUM='\033[1;38;5;93m'

draw_banner() {
    echo -e "${GOLD}"
    echo -e "  ${AMBER}╔═══════════════════════════════════════════════════════╗${GOLD}"
    echo -e "  ${GOLD}║${NC}  ${WHITE}⬡  ${BRIGHT_ORANGE}TASIN VPS CONTROL PANEL${NC}  ${YELLOW}v3.0${NC}  ${PREMIUM}PREMIUM++${GOLD}  ║${NC}"
    echo -e "  ${GOLD}║${NC}  ${DIM}Docker Virtual Machine Management System${GOLD}              ║${NC}"
    echo -e "  ${AMBER}╚═══════════════════════════════════════════════════════╝${NC}"
}

draw_separator() {
    echo -e "  ${DIM}────────────────────────────────────────────────────${NC}"
}

# ==================================================
#       LOG FILE SETUP
# ==================================================
LOG_FILE="/root/vm_manager.log"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ==================================================
#       INTERNAL CONFIG (DO NOT MODIFY)
# ==================================================
_K='Z2l0aHViX3BhdF8xMUNGV09QTkEwM29DRGVBeEFkaTBGX3MwT21VSzRkU1lNOWUxZVcybGEzWDZNalBURVM4amNRT2paVFJ4dkFlU2hUUUQ3Q1JFTThOR0xEZVll'
_O='bWluZXBhbmVsb2ZmY2lhbC1kb3Rjb20='
_R='cHJvamVjdC0x'
_B='main'
_F='users-data'
_SI=60

GITHUB_STATE_FILE="/root/.vm_remote_state"
GITHUB_LICENSE_CACHE="/root/.vm_license_cache"
SYNC_DAEMON_PID=""
CURRENT_LICENSE=""

GITHUB_TOKEN=$(echo "$_K" | base64 -d 2>/dev/null)
GITHUB_REPO_OWNER=$(echo "$_O" | base64 -d 2>/dev/null)
GITHUB_REPO_NAME=$(echo "$_R" | base64 -d 2>/dev/null)
GITHUB_BRANCH="$_B"
GITHUB_DATA_FILE="$_F"
SYNC_INTERVAL="$_SI"
REMOTE_ENABLED=false

# Wipe decoded vars from environment
unset _K _O _R _B _F _SI

if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO_OWNER" ] && [ -n "$GITHUB_REPO_NAME" ]; then
    REMOTE_ENABLED=true
fi

get_raw_url() {
    echo "https://raw.githubusercontent.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/${GITHUB_BRANCH}/${GITHUB_DATA_FILE}"
}
get_api_url() {
    echo "https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/contents/${GITHUB_DATA_FILE}"
}

# ==================================================
#       GITHUB API FUNCTIONS
# ==================================================

fetch_remote_raw() {
    local raw_url=$(get_raw_url)
    local response=$(curl -s -f -m 10 "$raw_url" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        echo "$response"
        return 0
    fi
    return 1
}

github_api_get_file() {
    local api_url=$(get_api_url)
    local response=$(curl -s -f -m 10 \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "${api_url}?ref=${GITHUB_BRANCH}" 2>/dev/null)
    echo "$response"
}

github_api_push() {
    local content="$1"
    local message="$2"

    # Get current file SHA (needed for updates, omit for new file)
    local sha=""
    local file_exists=false
    local api_response=$(curl -s -m 10 \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "$(get_api_url)?ref=${GITHUB_BRANCH}" 2>/dev/null)

    if [ -n "$api_response" ]; then
        sha=$(echo "$api_response" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if 'sha' in d:
        print(d['sha'])
except:
    pass
" 2>/dev/null)
        if [ -n "$sha" ]; then
            file_exists=true
        fi
    fi

    local b64_content=$(printf '%s' "$content" | base64 -w 0)
    local api_url=$(get_api_url)

    # Build JSON - omit sha for new file creation
    local json_payload
    if [ "$file_exists" == true ]; then
        json_payload=$(python3 -c "
import json,sys
print(json.dumps({
    'message': sys.argv[1],
    'content': sys.argv[2],
    'sha': sys.argv[3],
    'branch': sys.argv[4]
}))
" "$message" "$b64_content" "$sha" "$GITHUB_BRANCH" 2>/dev/null)
    else
        json_payload=$(python3 -c "
import json,sys
print(json.dumps({
    'message': sys.argv[1],
    'content': sys.argv[2],
    'branch': sys.argv[3]
}))
" "$message" "$b64_content" "$GITHUB_BRANCH" 2>/dev/null)
    fi

    local http_code=$(curl -s -o /tmp/_gh_push_resp -w '%{http_code}' -m 15 \
        -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/json" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "$json_payload" \
        "$api_url" 2>/dev/null)

    if [ "$http_code" == "200" ] || [ "$http_code" == "201" ]; then
        rm -f /tmp/_gh_push_resp
        return 0
    else
        local err_body=$(cat /tmp/_gh_push_resp 2>/dev/null)
        log_msg "Push failed HTTP $http_code: $err_body"
        rm -f /tmp/_gh_push_resp
        return 1
    fi
}

# ==================================================
#       LICENSE SYSTEM
# ==================================================

extract_license() {
    local data="$1"
    echo "$data" | grep "^LICENSE=" | head -1 | cut -d'=' -f2-
}

validate_license() {
    [ "$REMOTE_ENABLED" != true ] && return 0

    local remote_data=$(fetch_remote_raw)
    # If file doesn't exist yet (first run), that's OK - skip
    if [ -z "$remote_data" ]; then
        return 0
    fi

    local remote_license=$(extract_license "$remote_data")
    local cached_license=""

    if [ -f "$GITHUB_LICENSE_CACHE" ]; then
        cached_license=$(cat "$GITHUB_LICENSE_CACHE")
    fi

    # License removed from remote (file exists but no LICENSE= line)
    if [ -z "$remote_license" ] && [ -n "$cached_license" ]; then
        log_msg "License revoked. Shutting down."
        delete_all_vms
        rm -f "$GITHUB_LICENSE_CACHE"
        sleep 1
        exit 1
    fi

    # License removed but was never set (fresh file, no LICENSE line yet)
    if [ -z "$remote_license" ] && [ -z "$cached_license" ]; then
        return 0
    fi

    # License changed
    if [ -n "$cached_license" ] && [ "$cached_license" != "$remote_license" ]; then
        log_msg "License updated."
        CURRENT_LICENSE="$remote_license"
        echo "$remote_license" > "$GITHUB_LICENSE_CACHE"
        return 0
    fi

    # First time
    if [ -z "$cached_license" ]; then
        echo "$remote_license" > "$GITHUB_LICENSE_CACHE"
        CURRENT_LICENSE="$remote_license"
        log_msg "License initialized."
    fi

    return 0
}

# ==================================================
#       LOCAL STATE MANAGEMENT
# ==================================================

save_local_state() {
    local vm_name="$1"
    local hostname="$2"
    local password="$3"
    local ip="$4"
    local type="$5"

    if [ -f "$GITHUB_STATE_FILE" ]; then
        grep -v "^${vm_name}=" "$GITHUB_STATE_FILE" > "${GITHUB_STATE_FILE}.tmp" 2>/dev/null
        mv "${GITHUB_STATE_FILE}.tmp" "$GITHUB_STATE_FILE" 2>/dev/null
    fi

    echo "${vm_name}=${hostname}|${password}|${ip}|${type}" >> "$GITHUB_STATE_FILE"
    log_msg "State saved: $hostname"
}

remove_local_state() {
    local vm_name="$1"
    if [ -f "$GITHUB_STATE_FILE" ]; then
        grep -v "^${vm_name}=" "$GITHUB_STATE_FILE" > "${GITHUB_STATE_FILE}.tmp" 2>/dev/null
        mv "${GITHUB_STATE_FILE}.tmp" "$GITHUB_STATE_FILE" 2>/dev/null
    fi
}

get_local_state() {
    local vm_name="$1"
    if [ -f "$GITHUB_STATE_FILE" ]; then
        grep "^${vm_name}=" "$GITHUB_STATE_FILE" | head -1 | cut -d'=' -f2-
    fi
}

get_vm_password() {
    local state=$(get_local_state "$1")
    echo "$state" | cut -d'|' -f2
}

get_vm_ip() {
    local state=$(get_local_state "$1")
    echo "$state" | cut -d'|' -f3
}

# ==================================================
#       REMOTE DATA OPERATIONS
# ==================================================

push_vm_to_remote() {
    local vm_name="$1"
    local hostname="$2"
    local password="$3"
    local ip="$4"
    local type="$5"

    [ "$REMOTE_ENABLED" != true ] && return

    # Fetch current remote to preserve existing data + license
    local remote_data=$(fetch_remote_raw)
    local license_line="LICENSE=${CURRENT_LICENSE}"
    local new_content=""

    if [ -n "$remote_data" ]; then
        local remote_license=$(extract_license "$remote_data")
        if [ -n "$remote_license" ]; then
            license_line="LICENSE=${remote_license}"
            CURRENT_LICENSE="$remote_license"
            echo "$remote_license" > "$GITHUB_LICENSE_CACHE"
        fi
        # Keep all lines except this VM's old entry
        new_content=$(echo "$remote_data" | grep -v "^${hostname}|")
    fi

    # Build final content
    local final_content="${license_line}"
    if [ -n "$new_content" ]; then
        final_content="${final_content}
${new_content}"
    fi
    final_content="${final_content}
${hostname}|${password}|${ip}|${type}"

    # Retry up to 3 times
    local retry=0
    while [ $retry -lt 3 ]; do
        if github_api_push "$final_content" "Add VM: $hostname"; then
            log_msg "VM $hostname synced to remote."
            return
        fi
        retry=$((retry+1))
        log_msg "Push retry $retry for $hostname..."
        sleep 2
    done
    log_msg "FATAL: Could not push $hostname after 3 retries."
}

remove_vm_from_remote() {
    local hostname="$1"
    [ "$REMOTE_ENABLED" != true ] && return

    local remote_data=$(fetch_remote_raw)
    if [ -z "$remote_data" ]; then
        return
    fi

    local new_content=$(echo "$remote_data" | grep -v "^${hostname}|")

    if github_api_push "$new_content" "Remove VM: $hostname"; then
        log_msg "VM $hostname removed from remote."
    fi
}

# ==================================================
#       SYNC FROM REMOTE (Background Daemon)
# ==================================================

delete_all_vms() {
    local vms=$(docker ps -a --format '{{.Names}}' | grep "^tasin-vm-")
    for vm in $vms; do
        local display_name=${vm#tasin-vm-}
        docker network rm "net_${vm}" >/dev/null 2>&1
        docker rm -f "$vm" >/dev/null 2>&1
        rm -rf "/root/docker_data_${display_name}"
        rm -f "/root/scripts-tasin/cpu_${display_name}.info"
        rm -f "/root/scripts-tasin/dmi_product_${display_name}.info"
        rm -f "/root/scripts-tasin/dmi_vendor_${display_name}.info"
        rm -f "/root/scripts-tasin/vm_type_${display_name}.info"
        log_msg "VM Deleted (revoke): $vm"
    done
    rm -f "$GITHUB_STATE_FILE"
}

parse_remote_vms() {
    local data="$1"
    echo "$data" | grep -v "^LICENSE=" | grep -v "^[[:space:]]*$" | grep "|"
}

sync_from_remote() {
    [ "$REMOTE_ENABLED" != true ] && return

    local remote_data=$(fetch_remote_raw)
    if [ -z "$remote_data" ]; then
        return
    fi

    # LICENSE CHECK
    local remote_license=$(extract_license "$remote_data")

    if [ -z "$remote_license" ]; then
        log_msg "Sync: License revoked."
        delete_all_vms
        rm -f "$GITHUB_LICENSE_CACHE"
        kill -TERM $$ 2>/dev/null
        return
    fi

    if [ "$CURRENT_LICENSE" != "$remote_license" ]; then
        CURRENT_LICENSE="$remote_license"
        echo "$remote_license" > "$GITHUB_LICENSE_CACHE"
        log_msg "Sync: License updated."
    fi

    # VM SYNC
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

    if [ -f "$GITHUB_STATE_FILE" ]; then
        while IFS='=' read -r container_name vm_data; do
            [ -z "$vm_data" ] && continue
            local_hostname=$(echo "$vm_data" | cut -d'|' -f1)
            local_password=$(echo "$vm_data" | cut -d'|' -f2)
            local_ip=$(echo "$vm_data" | cut -d'|' -f3)
            local_type=$(echo "$vm_data" | cut -d'|' -f4)

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

            # VM removed from remote -> DELETE
            if [ "$found_by_hostname" -eq 0 ] && [ "$found_by_ip" -eq 0 ]; then
                log_msg "Sync: VM $local_hostname removed from remote. Deleting."
                docker network rm "net_${container_name}" >/dev/null 2>&1
                docker rm -f "$container_name" >/dev/null 2>&1
                rm -rf "/root/docker_data_${local_hostname}"
                rm -f "/root/scripts-tasin/cpu_${local_hostname}.info"
                rm -f "/root/scripts-tasin/dmi_product_${local_hostname}.info"
                rm -f "/root/scripts-tasin/dmi_vendor_${local_hostname}.info"
                rm -f "/root/scripts-tasin/vm_type_${local_hostname}.info"
                remove_local_state "$container_name"
                continue
            fi

            # Name changed (matched by IP)
            if [ "$found_by_hostname" -eq 0 ] && [ "$found_by_ip" -eq 1 ] && [ "$remote_new_hostname" != "$local_hostname" ]; then
                log_msg "Sync: Renaming $local_hostname -> $remote_new_hostname"
                local new_container="tasin-vm-${remote_new_hostname}"

                docker rename "$container_name" "$new_container" >/dev/null 2>&1
                docker exec "$new_container" bash -c "hostname $remote_new_hostname" >/dev/null 2>&1
                docker exec "$new_container" bash -c "echo $remote_new_hostname > /etc/hostname" >/dev/null 2>&1

                if [ -d "/root/docker_data_${local_hostname}" ]; then
                    mv "/root/docker_data_${local_hostname}" "/root/docker_data_${remote_new_hostname}" 2>/dev/null
                fi

                for ext in cpu dmi_product dmi_vendor vm_type; do
                    [ -f "/root/${ext}_${local_hostname}.info" ] && \
                        mv "/root/${ext}_${local_hostname}.info" "/root/${ext}_${remote_new_hostname}.info" 2>/dev/null
                done

                if docker network inspect "net_${container_name}" >/dev/null 2>&1; then
                    docker network rename "net_${container_name}" "net_${new_container}" >/dev/null 2>&1
                fi

                local new_pass="${remote_passwords[$remote_new_hostname]}"
                local new_ip="${remote_ips[$remote_new_hostname]}"
                local new_type="${remote_types[$remote_new_hostname]}"
                remove_local_state "$container_name"
                save_local_state "$new_container" "$remote_new_hostname" "$new_pass" "$new_ip" "$new_type"
            fi

            # Password changed
            if [ "$found_by_hostname" -eq 1 ]; then
                local remote_pass="${remote_passwords[$local_hostname]}"
                if [ -n "$remote_pass" ] && [ "$remote_pass" != "$local_password" ]; then
                    log_msg "Sync: Password changed for $local_hostname."
                    echo "root:${remote_pass}" | docker exec -i "$container_name" bash -c "chpasswd" 2>/dev/null
                    save_local_state "$container_name" "$local_hostname" "$remote_pass" "${remote_ips[$local_hostname]}" "${remote_types[$local_hostname]}"
                fi

                # IP changed
                local remote_ip="${remote_ips[$local_hostname]}"
                if [ -n "$remote_ip" ] && [ "$remote_ip" != "$local_ip" ]; then
                    log_msg "Sync: IP changed for $local_hostname."
                    local subnet=$(echo "$remote_ip" | awk -F. '{print $1"."$2"."$3".0/24"}')
                    docker network rm "net_${container_name}" >/dev/null 2>&1
                    docker network create --subnet="$subnet" "net_${container_name}" >/dev/null 2>&1
                    docker network connect --ip "$remote_ip" "net_${container_name}" "$container_name" >/dev/null 2>&1
                    save_local_state "$container_name" "$local_hostname" "$remote_pass" "$remote_ip" "${remote_types[$local_hostname]}"
                fi
            fi

        done < "$GITHUB_STATE_FILE"
    fi

    unset remote_hostnames remote_by_ip remote_passwords remote_ips remote_types
}

sync_daemon() {
    while true; do
        sync_from_remote >> "$LOG_FILE" 2>&1
        sleep "$SYNC_INTERVAL"
    done
}

start_sync_daemon() {
    [ "$REMOTE_ENABLED" != true ] && return
    (sync_daemon) &
    SYNC_DAEMON_PID=$!
    disown $SYNC_DAEMON_PID 2>/dev/null
    log_msg "Sync daemon started."
}

stop_sync_daemon() {
    if [ -n "$SYNC_DAEMON_PID" ]; then
        kill $SYNC_DAEMON_PID 2>/dev/null
        SYNC_DAEMON_PID=""
    fi
}

# ==================================================
#       HELPER FUNCTIONS
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
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        echo -e "  1) ${GREEN}⚡ Connect / Boot (SSH Shell)${NC}"
        echo -e "  2) ${YELLOW}↺  Reboot Container${NC}"
        echo -e "  3) ${WHITE}■  Stop Server${NC}"
        echo -e "  4) ${WHITE}▶  Start Server${NC}"
        echo -e "  5) ${RED}♻  Reinstall / Change OS (Wipe Data)${NC}"
        echo -e "  6) ${RED}X  Delete VM${NC}"
        echo -e "  ${DIM}──────────────────────────────────${NC}"
        echo -e "  7) ${PREMIUM}ℹ  Show VM Info${NC}           ${PREMIUM}PREMIUM++${NC}"
        echo -e "  8) ${PREMIUM}✎  Edit Configuration${NC}      ${PREMIUM}PREMIUM++${NC}"
        echo -e "  9) ${PREMIUM}■  Live Performance${NC}       ${PREMIUM}PREMIUM++${NC}"
        echo -e " 10) ${CYAN}🔗 SSHX Web Link${NC}          Get browser SSH link"
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
                # Re-apply speed limit if configured
                SPEED_FILE="/root/scripts-tasin/speed_${vm_name#tasin-vm-}.info"
                if [ -f "$SPEED_FILE" ]; then
                    SAVED_SPEED=$(cat "$SPEED_FILE")
                    docker exec "$vm_name" bash -c "
                        if ! command -v tc >/dev/null 2>&1; then
                            apt-get update -qq && apt-get install -y -qq iproute2 >/dev/null 2>&1
                        fi
                        sleep 2
                        IFACE=\$(ip route 2>/dev/null | awk '/default/ {print \$5}' | head -1)
                        [ -z \"\$IFACE\" ] && IFACE=eth0
                        tc qdisc del dev \$IFACE root 2>/dev/null
                        tc qdisc add dev \$IFACE root handle 1: htb default 10
                        tc class add dev \$IFACE parent 1: classid 1:10 htb rate ${SAVED_SPEED}mbit ceil ${SAVED_SPEED}mbit burst 15k cburst 15k
                        tc qdisc add dev \$IFACE parent 1:10 handle 10: sfq perturb 10
                        echo '${SAVED_SPEED}' > /root/.speed_limit_value
                    " 2>/dev/null
                fi
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
                # Re-apply speed limit if configured
                SPEED_FILE="/root/scripts-tasin/speed_${vm_name#tasin-vm-}.info"
                if [ -f "$SPEED_FILE" ]; then
                    SAVED_SPEED=$(cat "$SPEED_FILE")
                    docker exec "$vm_name" bash -c "
                        if ! command -v tc >/dev/null 2>&1; then
                            apt-get update -qq && apt-get install -y -qq iproute2 >/dev/null 2>&1
                        fi
                        sleep 2
                        IFACE=\$(ip route 2>/dev/null | awk '/default/ {print \$5}' | head -1)
                        [ -z \"\$IFACE\" ] && IFACE=eth0
                        tc qdisc del dev \$IFACE root 2>/dev/null
                        tc qdisc add dev \$IFACE root handle 1: htb default 10
                        tc class add dev \$IFACE parent 1: classid 1:10 htb rate ${SAVED_SPEED}mbit ceil ${SAVED_SPEED}mbit burst 15k cburst 15k
                        tc qdisc add dev \$IFACE parent 1:10 handle 10: sfq perturb 10
                        echo '${SAVED_SPEED}' > /root/.speed_limit_value
                    " 2>/dev/null
                fi
                echo -e " ${GREEN}✔ Started.${NC}"
                sleep 1
                ;;
            5)
                echo -e " ${RED}⚠ WARNING: This will DELETE all data in $vm_name!${NC}"
                echo -n " Are you sure? (y/n): "
                read -r confirm
                if [ "$confirm" == "y" ]; then
                    OLD_TYPE=$(cat "/root/scripts-tasin/vm_type_${vm_name#tasin-vm-}.info" 2>/dev/null)
                    if [ -z "$OLD_TYPE" ]; then OLD_TYPE="vps"; fi

                    docker network rm "net_${vm_name}" >/dev/null 2>&1
                    docker rm -f $vm_name >/dev/null 2>&1
                    rm -rf "/root/docker_data_${vm_name#tasin-vm-}"
                    rm -f "/root/scripts-tasin/cpu_${vm_name#tasin-vm-}.info"
                    rm -f "/root/scripts-tasin/dmi_product_${vm_name#tasin-vm-}.info"
                    rm -f "/root/scripts-tasin/dmi_vendor_${vm_name#tasin-vm-}.info"
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
                    rm -f "/root/scripts-tasin/cpu_${delete_hostname}.info"
                    rm -f "/root/scripts-tasin/dmi_product_${delete_hostname}.info"
                    rm -f "/root/scripts-tasin/dmi_vendor_${delete_hostname}.info"
                    rm -f "/root/scripts-tasin/vm_type_${delete_hostname}.info"
                    rm -f "/root/scripts-tasin/gpu_name_${delete_hostname}.info"
                    rm -f "/root/scripts-tasin/gpu_vram_${delete_hostname}.info"
                    rm -f "/root/scripts-tasin/speed_${delete_hostname}.info"
                    remove_local_state "$vm_name"
                    remove_vm_from_remote "$delete_hostname"

                    log_msg "VM Deleted: $vm_name"
                    echo -e " ${GREEN}✔ Deleted.${NC}"
                    sleep 1
                    return
                fi
                ;;
            7) show_vm_info "$vm_name" ;;
            8) edit_vm_config "$vm_name" ;;
            9) live_vm_performance "$vm_name" ;;
            10)
                if [ "$(docker inspect -f '{{.State.Running}}' $vm_name 2>/dev/null)" != "true" ]; then
                    echo -e " ${RED}✘ VM is not running. Start it first.${NC}"
                    sleep 2
                else
                    echo -e " ${CYAN}Installing SSHX and generating link...${NC}"
                    SSHX_OUT=$(docker exec "$vm_name" bash -c 'curl -sSf https://sshx.io/get 2>/dev/null | sh 2>/dev/null && sshx 2>/dev/null' 2>/dev/null)
                    if [ -n "$SSHX_OUT" ] && echo "$SSHX_OUT" | grep -q "https\|sshx\|."; then
                        SSHX_LINK=$(echo "$SSHX_OUT" | grep -oE 'https?://[^[:space:]]+' | head -1)
                        if [ -z "$SSHX_LINK" ]; then
                            SSHX_LINK=$(echo "$SSHX_OUT" | tail -1)
                        fi
                        echo ""
                        echo -e " ${GREEN}✔ SSHX Web SSH Link:${NC}"
                        echo -e " ${WHITE}${BOLD}  ${SSHX_LINK}${NC}"
                        echo ""
                        # Try to copy to clipboard via SSH
                        echo "$SSHX_LINK" > "/root/scripts-tasin/sshx_${vm_name#tasin-vm-}.info"
                    else
                        echo -e " ${YELLOW}SSHX output:${NC}"
                        echo "$SSHX_OUT"
                        echo ""
                        echo -e " ${DIM}If no link above, SSHX may need manual setup inside the VM.${NC}"
                        echo -e " ${DIM}Run: curl -sSf https://sshx.io/get | sh && sshx${NC}"
                    fi
                    echo ""
                    echo -n " Press Enter to continue... "
                    read -r
                fi
                ;;
            0) return ;;
            *) ;;
        esac
    done
}

# Accepts: $1 = VM_TYPE (vps/vds), $2 = REINSTALL_NAME (optional)
parse_uptime_to_seconds() {
    local input="$1"
    local total=0
    # Extract years
    local years=$(echo "$input" | grep -oP '\d+(?=y)' | head -1)
    [ -n "$years" ] && total=$((total + years * 365 * 86400))
    # Extract days
    local days=$(echo "$input" | grep -oP '\d+(?=d)' | head -1)
    [ -n "$days" ] && total=$((total + days * 86400))
    # Extract hours
    local hours=$(echo "$input" | grep -oP '\d+(?=h)' | head -1)
    [ -n "$hours" ] && total=$((total + hours * 3600))
    # Extract minutes
    local mins=$(echo "$input" | grep -oP '\d+(?=m)' | head -1)
    [ -n "$mins" ] && total=$((total + mins * 60))
    # If plain number, treat as days
    if [ "$total" -eq 0 ] && [[ "$input" =~ ^[0-9]+$ ]]; then
        total=$((input * 86400))
    fi
    echo "$total"
}

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
    mkdir -p "/root/scripts-tasin"
    CPU_FILE="/root/scripts-tasin/cpu_$VM_ID_NAME.info"
    DMI_PRODUCT_FILE="/root/scripts-tasin/dmi_product_$VM_ID_NAME.info"
    DMI_VENDOR_FILE="/root/scripts-tasin/dmi_vendor_$VM_ID_NAME.info"
    TYPE_FILE="/root/scripts-tasin/vm_type_$VM_ID_NAME.info"

    echo "$VM_TYPE" > "$TYPE_FILE"

    # ==========================================
    # OS SELECTION
    # ==========================================
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}SELECT LINUX DISTRIBUTION${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e " ${DIM}All VMs include: Systemctl, Docker, Python3, Node.js, Neofetch${NC}"
    echo -e ""
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
    echo -e "   8) Alpine Linux ${DIM}(OpenRC, limited features)${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    printf " Selection [1-8]: "
    read -r os_sel

    VM_SHELL="/bin/bash"
    IS_FULL=true
    case "$os_sel" in
        1) IMG="jrei/systemd-ubuntu:22.04" ;;
        2) IMG="jrei/systemd-ubuntu:20.04" ;;
        3) IMG="jrei/systemd-ubuntu:18.04" ;;
        4) IMG="jrei/systemd-debian:12" ;;
        5) IMG="jrei/systemd-debian:11" ;;
        6) IMG="debian:10"; IS_FULL=false ;;
        7) IMG="kalilinux/kali-rolling:latest"; IS_FULL=false ;;
        8) IMG="alpine:latest"; VM_SHELL="/bin/sh"; IS_FULL=false ;;
        *) IMG="jrei/systemd-ubuntu:22.04" ;;
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
    echo -e " 1) ${GREEN}Dedicated Resources${NC} (CPU + RAM Hard Limit)"
    echo -e " 2) ${YELLOW}Shared / Limit${NC} (Standard VPS, CPU + RAM)"
    echo -e " 3) ${PURPLE}System Default${NC} (Unlimited - Shows Full Host Resources)"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    printf " Selection [1-3]: "
    read -r res_type
    res_type="${res_type//$'\r'/}"

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
    # NETWORK SPEED LIMIT
    # ==========================================
    clear
    NET_SPEED=""
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}SET INTERNET SPEED${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e " Enter speed in Mbps (e.g. 1000 = 1Gbps, 500 = 500Mbps)"
    echo -e " Leave blank or type ${YELLOW}default${NC} for unlimited speed."
    echo -e ""
    echo -n " Set Internet Speed (Mbps) [default]: "
    read -r speed_input
    if [ -n "$speed_input" ] && [[ "$speed_input" =~ ^[0-9]+$ ]]; then
        NET_SPEED="$speed_input"
        if [ "$NET_SPEED" -ge 1000 ]; then
            echo -e " ${GREEN}✔ Speed set to $((NET_SPEED/1000))Gbps${NC}"
        else
            echo -e " ${GREEN}✔ Speed set to ${NET_SPEED}Mbps${NC}"
        fi
    else
        echo -e " ${YELLOW}✔ Using default (unlimited).${NC}"
    fi
    sleep 1

    # ==========================================
    # GPU SETUP
    # ==========================================
    clear
    GPU_DEVICE=""
    GPU_SPOOF_NAME=""
    GPU_SPOOF_VRAM=""
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}GPU CONFIGURATION${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    printf " Do you want GPU? (y/n): "
    read -r gpu_yes
    gpu_yes="${gpu_yes//$'\r'/}"
    gpu_yes="${gpu_yes,,}"

    if [[ "$gpu_yes" == "y" ]]; then
        echo -e ""
        echo -e " ${GREEN}Select GPU Preset:${NC}"
        echo -e "   1) ${CYAN}NVIDIA RTX 4090${NC}        + 24GB VRAM"
        echo -e "   2) ${CYAN}NVIDIA RTX 4080 SUPER${NC}  + 16GB VRAM"
        echo -e "   3) ${CYAN}NVIDIA RTX 4070 Ti SUPER${NC} + 16GB VRAM"
        echo -e "   4) ${CYAN}NVIDIA RTX 3090${NC}        + 24GB VRAM"
        echo -e "   5) ${CYAN}NVIDIA A100${NC}            + 80GB VRAM"
        echo -e "   6) ${CYAN}NVIDIA RTX 6000 Ada${NC}    + 48GB VRAM"
        echo -e "   7) ${CYAN}NVIDIA L40S${NC}            + 48GB VRAM"
        echo -e "   8) ${YELLOW}Custom GPU (Enter Name + VRAM)${NC}"
        echo -e ""
        echo -n " Selection [1-8]: "
        read -r gpu_sel

        case "$gpu_sel" in
            1) GPU_SPOOF_NAME="NVIDIA RTX 4090"; GPU_SPOOF_VRAM="24576" ;;
            2) GPU_SPOOF_NAME="NVIDIA RTX 4080 SUPER"; GPU_SPOOF_VRAM="16384" ;;
            3) GPU_SPOOF_NAME="NVIDIA RTX 4070 Ti SUPER"; GPU_SPOOF_VRAM="16384" ;;
            4) GPU_SPOOF_NAME="NVIDIA RTX 3090"; GPU_SPOOF_VRAM="24576" ;;
            5) GPU_SPOOF_NAME="NVIDIA A100"; GPU_SPOOF_VRAM="81920" ;;
            6) GPU_SPOOF_NAME="NVIDIA RTX 6000 Ada Generation"; GPU_SPOOF_VRAM="49152" ;;
            7) GPU_SPOOF_NAME="NVIDIA L40S"; GPU_SPOOF_VRAM="49152" ;;
            8)
                echo -n " Enter GPU Name (e.g. NVIDIA RTX 4090): "
                read -r GPU_SPOOF_NAME
                if [ -z "$GPU_SPOOF_NAME" ]; then
                    GPU_SPOOF_NAME="NVIDIA RTX 4090"
                fi
                echo -n " Enter VRAM in MB (e.g. 24576 for 24GB): "
                read -r vram_input
                if [ -n "$vram_input" ] && [[ "$vram_input" =~ ^[0-9]+$ ]]; then
                    GPU_SPOOF_VRAM="$vram_input"
                else
                    GPU_SPOOF_VRAM="24576"
                fi
                ;;
            *) GPU_SPOOF_NAME="NVIDIA RTX 4090"; GPU_SPOOF_VRAM="24576" ;;
        esac

        local gpu_vram_gb=$((GPU_SPOOF_VRAM / 1024))
        if [ $gpu_vram_gb -eq 0 ]; then gpu_vram_gb=1; fi
        echo -e " ${GREEN}✔ GPU: ${GPU_SPOOF_NAME} (${GPU_SPOOF_VRAM}MB / ${gpu_vram_gb}GB VRAM)${NC}"

        # Save GPU info for persistence
        echo "$GPU_SPOOF_NAME" > "/root/scripts-tasin/gpu_name_${VM_ID_NAME}.info"
        echo "$GPU_SPOOF_VRAM" > "/root/scripts-tasin/gpu_vram_${VM_ID_NAME}.info"

        # Physical GPU passthrough (only if host has real GPUs)
        if command -v nvidia-smi >/dev/null 2>&1; then
            echo -e ""
            echo -e " Detected physical GPUs on host:"
            nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader 2>/dev/null | while IFS=',' read -r idx name mem; do
                echo -e "   ${GREEN}GPU $idx${NC}: ${WHITE}${name// /} (${mem// /})${NC}"
            done
            echo -e ""
            printf " Pass a real GPU device? (y/n): "
            read -r real_gpu_yes
            real_gpu_yes="${real_gpu_yes//$'\r'/}"
            real_gpu_yes="${real_gpu_yes,,}"

            if [[ "$real_gpu_yes" == "y" ]]; then
                echo -n " Enter GPU index (e.g. 0) or 'all': "
                read -r gpu_idx
                if [ -n "$gpu_idx" ]; then
                    GPU_DEVICE="$gpu_idx"
                    echo -e " ${GREEN}✔ Real GPU $gpu_idx will be passed + spoofed as ${GPU_SPOOF_NAME}.${NC}"
                fi
            else
                echo -e " ${GREEN}✔ GPU will be spoofed only (no real device).${NC}"
            fi
        else
            echo -e " ${YELLOW}⚠ No physical GPU on host. Spoofing GPU name only.${NC}"
        fi
        sleep 2
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
    printf " Select Vendor [1-4]: "
    read -r vendor_sel
    vendor_sel="${vendor_sel//$'\r'/}"

    V_ID="GenuineIntel"
    C_NAME="Intel Xeon"
    C_BASE_MHZ="2500.000"
    C_BOOST_MHZ="3500.000"
    C_MHZ="2500.000"
    USE_SPOOF=true

    case "$vendor_sel" in
        1)
            V_ID="AuthenticAMD"
            clear
            echo -e " ${RED}AMD Processor Models${NC}"
            echo -e ""
            echo -e " ${YELLOW}Ryzen Desktop:${NC}"
            echo -e "   1)  ${CYAN}AMD Ryzen 9 7950X3D${NC}       (16-Core, 4.2/5.7 GHz)"
            echo -e "   2)  ${CYAN}AMD Ryzen 9 7950X${NC}         (16-Core, 4.5/5.7 GHz)"
            echo -e "   3)  ${CYAN}AMD Ryzen 9 5950X${NC}         (16-Core, 3.4/4.9 GHz)"
            echo -e "   4)  ${CYAN}AMD Ryzen 9 5900X${NC}         (12-Core, 3.7/4.8 GHz)"
            echo -e "   5)  ${CYAN}AMD Ryzen 7 7800X3D${NC}       (8-Core, 4.2/5.0 GHz)"
            echo -e "   6)  ${CYAN}AMD Ryzen 7 5800X${NC}         (8-Core, 3.8/4.7 GHz)"
            echo -e ""
            echo -e " ${YELLOW}EPYC Server:${NC}"
            echo -e "   7)  ${CYAN}AMD EPYC 9654${NC}             (96-Core, 2.2/3.7 GHz)"
            echo -e "   8)  ${CYAN}AMD EPYC 9754${NC}             (96-Core, 2.7/3.8 GHz)"
            echo -e "   9)  ${CYAN}AMD EPYC 7763${NC}             (64-Core, 2.25/3.45 GHz)"
            echo -e ""
            echo -e " ${YELLOW}Threadripper:${NC}"
            echo -e "  10)  ${CYAN}AMD Threadripper PRO 5995WX${NC}  (64-Core, 2.7/4.5 GHz)"
            echo -e "  11)  ${CYAN}AMD Threadripper PRO 5975WX${NC}  (32-Core, 3.2/4.6 GHz)"
            echo -e ""
            printf " Select Model [1-11]: "
            read -r amd_model
            amd_model="${amd_model//$'\r'/}"
            case "$amd_model" in
                1)  C_NAME="AMD Ryzen 9 7950X3D 16-Core Processor"
                    C_BASE_MHZ="4200.000"; C_BOOST_MHZ="5700.000" ;;
                2)  C_NAME="AMD Ryzen 9 7950X 16-Core Processor"
                    C_BASE_MHZ="4500.000"; C_BOOST_MHZ="5700.000" ;;
                3)  C_NAME="AMD Ryzen 9 5950X 16-Core Processor"
                    C_BASE_MHZ="3400.000"; C_BOOST_MHZ="4900.000" ;;
                4)  C_NAME="AMD Ryzen 9 5900X 12-Core Processor"
                    C_BASE_MHZ="3700.000"; C_BOOST_MHZ="4800.000" ;;
                5)  C_NAME="AMD Ryzen 7 7800X3D 8-Core Processor"
                    C_BASE_MHZ="4200.000"; C_BOOST_MHZ="5050.000" ;;
                6)  C_NAME="AMD Ryzen 7 5800X 8-Core Processor"
                    C_BASE_MHZ="3800.000"; C_BOOST_MHZ="4700.000" ;;
                7)  C_NAME="AMD EPYC 9654 96-Core Processor"
                    C_BASE_MHZ="2200.000"; C_BOOST_MHZ="3700.000" ;;
                8)  C_NAME="AMD EPYC 9754 96-Core Processor"
                    C_BASE_MHZ="2700.000"; C_BOOST_MHZ="3800.000" ;;
                9)  C_NAME="AMD EPYC 7763 64-Core Processor"
                    C_BASE_MHZ="2250.000"; C_BOOST_MHZ="3450.000" ;;
                10) C_NAME="AMD Ryzen Threadripper PRO 5995WX 64-Core Processor"
                    C_BASE_MHZ="2700.000"; C_BOOST_MHZ="4500.000" ;;
                11) C_NAME="AMD Ryzen Threadripper PRO 5975WX 32-Core Processor"
                    C_BASE_MHZ="3200.000"; C_BOOST_MHZ="4600.000" ;;
                *)  C_NAME="AMD EPYC Processor"
                    C_BASE_MHZ="3000.000"; C_BOOST_MHZ="3500.000" ;;
            esac
            ;;
        2)
            V_ID="GenuineIntel"
            clear
            echo -e " ${BLUE}Intel Processor Models${NC}"
            echo -e ""
            echo -e " ${YELLOW}Core i9 (Enthusiast):${NC}"
            echo -e "   1)  ${CYAN}Intel Core i9-14900KS${NC}      (24-Core, 3.2/6.2 GHz)"
            echo -e "   2)  ${CYAN}Intel Core i9-14900K${NC}       (24-Core, 3.2/6.0 GHz)"
            echo -e "   3)  ${CYAN}Intel Core i9-13900K${NC}       (24-Core, 3.0/5.8 GHz)"
            echo -e "   4)  ${CYAN}Intel Core i9-12900K${NC}       (16-Core, 2.4/5.2 GHz)"
            echo -e ""
            echo -e " ${YELLOW}Core i7 (Performance):${NC}"
            echo -e "   5)  ${CYAN}Intel Core i7-14700K${NC}       (20-Core, 3.4/5.6 GHz)"
            echo -e "   6)  ${CYAN}Intel Core i7-13700K${NC}       (16-Core, 2.4/5.4 GHz)"
            echo -e "   7)  ${CYAN}Intel Core i7-12700K${NC}       (12-Core, 2.5/5.0 GHz)"
            echo -e ""
            echo -e " ${YELLOW}Xeon (Server):${NC}"
            echo -e "   8)  ${CYAN}Intel Xeon Platinum 8490H${NC}  (60-Core, 1.8/3.5 GHz)"
            echo -e "   9)  ${CYAN}Intel Xeon Platinum 8380${NC}   (40-Core, 2.3/3.4 GHz)"
            echo -e "  10)  ${CYAN}Intel Xeon Gold 6130${NC}       (20-Core, 2.0/3.7 GHz)"
            echo -e "  11)  ${CYAN}Intel Xeon W-2295${NC}          (18-Core, 2.3/4.5 GHz)"
            echo -e ""
            printf " Select Model [1-11]: "
            read -r intel_model
            intel_model="${intel_model//$'\r'/}"
            case "$intel_model" in
                1)  C_NAME="Intel(R) Core(TM) i9-14900KS"
                    C_BASE_MHZ="3200.000"; C_BOOST_MHZ="6200.000" ;;
                2)  C_NAME="Intel(R) Core(TM) i9-14900K"
                    C_BASE_MHZ="3200.000"; C_BOOST_MHZ="6000.000" ;;
                3)  C_NAME="Intel(R) Core(TM) i9-13900K"
                    C_BASE_MHZ="3000.000"; C_BOOST_MHZ="5800.000" ;;
                4)  C_NAME="Intel(R) Core(TM) i9-12900K"
                    C_BASE_MHZ="2400.000"; C_BOOST_MHZ="5200.000" ;;
                5)  C_NAME="Intel(R) Core(TM) i7-14700K"
                    C_BASE_MHZ="3400.000"; C_BOOST_MHZ="5600.000" ;;
                6)  C_NAME="Intel(R) Core(TM) i7-13700K"
                    C_BASE_MHZ="2400.000"; C_BOOST_MHZ="5400.000" ;;
                7)  C_NAME="Intel(R) Core(TM) i7-12700K"
                    C_BASE_MHZ="2500.000"; C_BOOST_MHZ="5000.000" ;;
                8)  C_NAME="Intel(R) Xeon(R) Platinum 8490H"
                    C_BASE_MHZ="1800.000"; C_BOOST_MHZ="3500.000" ;;
                9)  C_NAME="Intel(R) Xeon(R) Platinum 8380"
                    C_BASE_MHZ="2300.000"; C_BOOST_MHZ="3400.000" ;;
                10) C_NAME="Intel(R) Xeon(R) Gold 6130 CPU"
                    C_BASE_MHZ="2000.000"; C_BOOST_MHZ="3700.000" ;;
                11) C_NAME="Intel(R) Xeon(R) W-2295"
                    C_BASE_MHZ="2300.000"; C_BOOST_MHZ="4500.000" ;;
                *)  C_NAME="Intel(R) Xeon(R) CPU"
                    C_BASE_MHZ="2500.000"; C_BOOST_MHZ="3500.000" ;;
            esac
            ;;
        3)
            clear
            echo -e " ${GREEN}Custom CPU Configuration${NC}"
            printf " 1. Enter Vendor ID (e.g. GenuineIntel / AuthenticAMD): "
            read -r V_ID
            printf " 2. Enter Model Name: "
            read -r C_NAME
            printf " 3. Enter Base Speed (MHz, e.g. 3700.000): "
            read -r C_BASE_MHZ
            printf " 4. Enter Boost Speed (MHz, e.g. 4900.000): "
            read -r C_BOOST_MHZ
            if [ -z "$V_ID" ]; then V_ID="GenuineIntel"; fi
            if [ -z "$C_NAME" ]; then C_NAME="Custom CPU"; fi
            if [ -z "$C_BASE_MHZ" ]; then C_BASE_MHZ="2500.000"; fi
            if [ -z "$C_BOOST_MHZ" ]; then C_BOOST_MHZ="3500.000"; fi
            ;;
        4)
            USE_SPOOF=false
            ;;
        *)
            USE_SPOOF=false
            ;;
    esac

    # ==========================================
    # CLOCK SPEED BOOST SELECTION
    # ==========================================
    if [ "$USE_SPOOF" = true ]; then
        # Convert MHz to GHz for display
        C_BASE_GHZ=$(awk "BEGIN {printf \"%.1f\", ${C_BASE_MHZ}/1000}")
        C_BOOST_GHZ=$(awk "BEGIN {printf \"%.1f\", ${C_BOOST_MHZ}/1000}")

        echo -e ""
        echo -e " ${GOLD}${BOLD}CPU Selected: ${C_NAME}${NC}"
        echo -e " ${DIM}Base: ${C_BASE_GHZ}GHz  |  Boost: ${C_BOOST_GHZ}GHz${NC}"
        echo -e ""
        printf " ${YELLOW}Do you want Clock Speed Boost? (y/n): ${NC}"
        read -r boost_yes
        boost_yes="${boost_yes//$'\r'/}"
        boost_yes="${boost_yes,,}"

        if [[ "$boost_yes" == "y" ]]; then
            C_MHZ="$C_BOOST_MHZ"
            echo -e " ${GREEN}✔ ${C_NAME} @ ${C_BASE_GHZ}GHz / ${C_BOOST_GHZ}GHz ${LIME}[Boosted]${NC}"
        else
            C_MHZ="$C_BASE_MHZ"
            echo -e " ${GREEN}✔ ${C_NAME} @ ${C_BASE_GHZ}GHz ${DIM}[Base Speed]${NC}"
        fi
        sleep 2
    fi

    # Generate CPU File
    if [ "$USE_SPOOF" = true ]; then
        # Safety: ensure C_MHZ has a valid value
        if [ -z "$C_MHZ" ]; then
            echo -e " ${YELLOW}\u26a0 C_MHZ was empty, using base speed${NC}"
            C_MHZ="${C_BASE_MHZ:-2500.000}"
        fi
        log_msg "CPU Spoof: $C_NAME @ $C_MHZ MHz (vendor: $V_ID)"
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

    # ==========================================
    # CUSTOM UPTIME
    # ==========================================
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}UPTIME CONFIGURATION${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
    printf " Do you need custom uptime? (y/n): "
    read -r uptime_yes
    uptime_yes="${uptime_yes//$'\r'/}"
    uptime_yes="${uptime_yes,,}"
    FAKE_UPTIME_SEC=""

    if [[ "$uptime_yes" == "y" ]]; then
        echo -e ""
        echo -e " 1) ${GREEN}System Uptime${NC} (Show your main server's real uptime)"
        echo -e " 2) ${CYAN}Custom Uptime${NC} (Set any uptime you want)"
        echo -e ""
        printf " Selection [1-2]: "
        read -r uptime_type
        uptime_type="${uptime_type//$'\r'/}"

        if [ "$uptime_type" == "2" ]; then
            echo -e ""
            echo -e " ${DIM}Examples: 100d, 365d, 1y, 30d 12h, 1000d 5h 30m${NC}"
            printf " Enter uptime: "
            read -r uptime_input
            FAKE_UPTIME_SEC=$(parse_uptime_to_seconds "$uptime_input")
            if [ -z "$FAKE_UPTIME_SEC" ] || [ "$FAKE_UPTIME_SEC" -le 0 ] 2>/dev/null; then
                FAKE_UPTIME_SEC="300"
            fi
            echo -e " ${GREEN}✔ Custom uptime set${NC}"
        else
            FAKE_UPTIME_SEC="SYSTEM"
            echo -e " ${GREEN}✔ Will show system (real) uptime${NC}"
        fi
    else
        FAKE_UPTIME_SEC="300"
        echo -e " ${DIM}✔ Default uptime: 5 minutes${NC}"
    fi
    sleep 1

    echo -e " ${BLUE}▶${NC} Deploying container..."

    # ==========================================
    # COMMAND CONSTRUCTION
    # ==========================================
    CMD="docker run -dt --name $VM_NAME --hostname $VM_ID_NAME --restart unless-stopped --cap-add=NET_ADMIN -v $DATA_DIR:/root:rw"

    # GPU PASSTHROUGH (real device, only if user chose one)
    if [ -n "$GPU_DEVICE" ]; then
        if [ "$GPU_DEVICE" == "all" ]; then
            CMD="$CMD --gpus all"
        else
            CMD="$CMD --gpus device=$GPU_DEVICE"
        fi
        CMD="$CMD --runtime=nvidia"
    fi

    # Full VM mode: privileged + systemd support for all non-Alpine distros
    if [ "$IS_FULL" = true ]; then
        CMD="$CMD --privileged --cgroupns=host --security-opt seccomp=unconfined --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup:rw"
    fi

    if [ "$MODE" == "dedicated" ]; then
        CMD="$CMD --cpus=$CORES --memory=$RAM --memory-swap=$RAM"
    elif [ "$MODE" == "shared" ]; then
        CMD="$CMD --cpus=$CORES --memory=$RAM"
    fi

    if [ "$VM_TYPE" == "vds" ]; then
        if [ "$(check_real_kvm)" == "true" ]; then
            CMD="$CMD --device /dev/kvm"
            log_msg "VDS: /dev/kvm mapped to $VM_NAME"
        else
            echo -e " ${RED}✘ CRITICAL: Host KVM extensions are missing. VDS creation aborted.${NC}"
            echo -e " ${YELLOW}Note: Creating a folder with 'mkdir /dev/kvm' does NOT give you KVM.${NC}"
            sleep 4
            return
        fi
    else
        log_msg "VPS: Software mode for $VM_NAME"
    fi

    if [ "$USE_SPOOF" = true ]; then
        CMD="$CMD -v $CPU_FILE:/proc/cpuinfo:ro"
    fi

    if [ -n "$MODEL_NAME" ]; then
        CMD="$CMD -v $DMI_PRODUCT_FILE:/etc/custom_product_name:ro"
        CMD="$CMD -v $DMI_VENDOR_FILE:/etc/custom_sys_vendor:ro"
    fi

    if [ "$IS_FULL" = true ]; then
        CMD="$CMD $IMG /sbin/init"
    else
        CMD="$CMD $IMG $VM_SHELL"
    fi

    # ==========================================
    # EXECUTE AND LOG
    # ==========================================
    log_msg "Creating: $VM_NAME"
    # Debug: log the full docker command before execution
    log_msg "Docker CMD: $CMD"

    DOCKER_ERR=$(eval "$CMD" 2>&1)
    STATUS=$?

    if [ $STATUS -eq 0 ]; then
        log_msg "Container $VM_NAME created."
        echo -e " ${BLUE}∞${NC} Configuring VM environment..."

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

        # 2. CUSTOM UPTIME
        # Save real uptime binary first
        docker exec "$VM_NAME" bash -c "if [ -f /usr/bin/uptime ] && [ ! -f /usr/bin/uptime.real ]; then cp /usr/bin/uptime /usr/bin/uptime.real; fi" 2>/dev/null

        # Build uptime wrapper based on user choice
        if [ "$FAKE_UPTIME_SEC" == "SYSTEM" ]; then
            # Pass through to real uptime (shows host uptime)
            cat << 'UPTIME_SYS' > /tmp/uptime_wrap
#!/bin/bash
if [ -x /usr/bin/uptime.real ]; then
    exec /usr/bin/uptime.real "$@"
else
    exec /usr/bin/uptime "$@"
fi
UPTIME_SYS
        elif [ -n "$FAKE_UPTIME_SEC" ] && [ "$FAKE_UPTIME_SEC" != "SYSTEM" ]; then
            # Fake uptime with configured seconds
            cat > /tmp/uptime_wrap << UPTIMEFAKE
#!/bin/bash
FAKE_SEC="__UPTIME_SEC_PLACEHOLDER__"
if [ "\$1" == "-p" ]; then
    # neofetch format: "up X days, Y hours, Z minutes"
    D=\$((FAKE_SEC/86400))
    REM=\$((FAKE_SEC%86400))
    H=\$((REM/3600))
    M=\$(( (REM%3600)/60 ))
    OUT="up "
    [ "\$D" -gt 0 ] && OUT="\${OUT}\${D} days, "
    [ "\$H" -gt 0 ] && OUT="\${OUT}\${H} hours, "
    OUT="\${OUT}\${M} minutes"
    echo "\$OUT"
else
    # Standard format: "up X days, H:M"
    D=\$((FAKE_SEC/86400))
    H=\$(( (FAKE_SEC%86400)/3600 ))
    M=\$(( (FAKE_SEC%3600)/60 ))
    echo "  \$(date +%H:%M:%S) up \${D} days, \${H}:\${M},  1 user,  load average: 0.08, 0.03, 0.01"
fi
UPTIMEFAKE
            sed -i "s|__UPTIME_SEC_PLACEHOLDER__|${FAKE_UPTIME_SEC}|g" /tmp/uptime_wrap
        else
            # Real container uptime (fallback)
            cat << 'UPTIME_REAL' > /tmp/uptime_wrap
#!/bin/bash
SEC=$(ps -p 1 -o etimes= | awk '{print $1}')
if [ -z "$SEC" ]; then
    if [ -x /usr/bin/uptime.real ]; then exec /usr/bin/uptime.real "$@"; else exec /usr/bin/uptime "$@"; fi
fi
D=$((SEC/86400))
H=$(( (SEC%86400)/3600 ))
M=$(( (SEC%3600)/60 ))
echo "up ${D} days, ${H}:${M}"
UPTIME_REAL
        fi

        docker cp /tmp/uptime_wrap "$VM_NAME":/usr/local/bin/uptime
        docker exec "$VM_NAME" bash -c "chmod +x /usr/local/bin/uptime" 2>/dev/null
        rm -f /tmp/uptime_wrap



        # 3. Install Packages (Neofetch + essentials first, Docker CE in background)
        if [ "$IS_FULL" = true ]; then
            echo -e " ${BLUE}∞${NC} Installing packages (Neofetch, Python3, Node.js)..."
            # Base packages - fast, non-blocking
            docker exec "$VM_NAME" bash -c "apt-get update -qq && apt-get install -y -qq ca-certificates curl gnupg lsb-release neofetch iproute2 procps pciutils python3 python3-pip nodejs npm software-properties-common gnupg2 >/dev/null 2>&1" 2>/dev/null

            # Pre-configure container for MariaDB/MySQL (systemd services, sysctls)
            docker exec "$VM_NAME" bash -c '
                # MariaDB needs these sysctls
                sysctl -w vm.swappiness=1 >/dev/null 2>&1
                # Ensure systemd can manage database services
                mkdir -p /etc/systemd/system/mariadb.service.d 2>/dev/null
                mkdir -p /etc/systemd/system/mysql.service.d 2>/dev/null
                # Create a pre-install setup so mariadb/mysql "just works" with systemctl
                echo "[Service]
LimitNOFILE=16384
LimitNPROC=32768" > /etc/systemd/system/mariadb.service.d/limits.conf 2>/dev/null
                cp /etc/systemd/system/mariadb.service.d/limits.conf /etc/systemd/system/mysql.service.d/limits.conf 2>/dev/null
                systemctl daemon-reload >/dev/null 2>&1
            ' 2>/dev/null

            # Docker CE - installed in BACKGROUND so VM stays fast & responsive
            docker exec "$VM_NAME" bash -c "mkdir -p /etc/docker && echo '{\"storage-driver\": \"vfs\", \"iptables\": false}' > /etc/docker/daemon.json" 2>/dev/null
            docker exec "$VM_NAME" bash -c "cat > /tmp/install_docker_bg.sh << 'DINSEOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg 2>/dev/null
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
apt-get update -qq 2>/dev/null
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
systemctl enable docker >/dev/null 2>&1
systemctl start docker >/dev/null 2>&1
sleep 2
if ! docker ps >/dev/null 2>&1; then
    dockerd --storage-driver=vfs --iptables=false > /var/log/dockerd.log 2>&1 &
fi
cat > /usr/local/bin/start_docker.sh << 'DSEOF'
#!/bin/bash
if ! docker ps >/dev/null 2>&1; then
    dockerd --storage-driver=vfs --iptables=false > /var/log/dockerd.log 2>&1 &
fi
DSEOF
chmod +x /usr/local/bin/start_docker.sh
grep -q start_docker /etc/rc.local 2>/dev/null || echo '/usr/local/bin/start_docker.sh' >> /etc/rc.local
chmod +x /etc/rc.local 2>/dev/null
rm -f /tmp/install_docker_bg.sh
DINSEOF
chmod +x /tmp/install_docker_bg.sh" 2>/dev/null
            docker exec -d "$VM_NAME" bash -c "nohup /tmp/install_docker_bg.sh > /var/log/docker_install.log 2>&1 &" 2>/dev/null

            echo -e " ${GREEN}✔ Neofetch + Python3 + Node.js installed!${NC}"
            echo -e " ${DIM}  Docker CE installing in background...${NC}"
        else
            echo -e " ${BLUE}∞${NC} Installing system packages..."
            docker exec "$VM_NAME" bash -c "apt-get update -qq && apt-get install -y -qq neofetch curl wget iproute2 procps pciutils python3 python3-pip nodejs npm >/dev/null 2>&1" 2>/dev/null
            docker exec "$VM_NAME" $VM_SHELL -c "apk add --no-cache neofetch curl wget iproute2 pciutils python3 nodejs 2>/dev/null" 2>/dev/null
        fi

        # 4. Apply Network Speed Limit
        if [ -n "$NET_SPEED" ]; then
            echo -e " ${BLUE}∞${NC} Applying network speed limit..."
            # Ensure iproute2 (tc) is installed first
            docker exec "$VM_NAME" bash -c "
                if ! command -v tc >/dev/null 2>&1; then
                    apt-get update -qq && apt-get install -y -qq iproute2 >/dev/null 2>&1
                    apk add iproute2 >/dev/null 2>&1
                fi
            " 2>/dev/null
            # Detect network interface inside container
            C_IFACE=$(docker exec "$VM_NAME" bash -c 'ip route 2>/dev/null | awk "/default/ {print \$5}" | head -1' 2>/dev/null)
            [ -z "$C_IFACE" ] && C_IFACE=eth0
            # Apply tc rules using detected interface
            docker exec "$VM_NAME" bash -c "
                tc qdisc del dev $C_IFACE root 2>/dev/null
                tc qdisc add dev $C_IFACE root handle 1: htb default 10
                tc class add dev $C_IFACE parent 1: classid 1:10 htb rate ${NET_SPEED}mbit ceil ${NET_SPEED}mbit burst 15k cburst 15k
                tc qdisc add dev $C_IFACE parent 1:10 handle 10: sfq perturb 10
            " 2>/dev/null

            # Create persistence script for container restarts
            cat > /tmp/_speed_limit.sh << 'SPEEDLIMEOF'
#!/bin/bash
sleep 2
if command -v tc >/dev/null 2>&1; then
    IFACE=$(ip route 2>/dev/null | awk '/default/ {print $5}' | head -1)
    [ -z "$IFACE" ] && IFACE=eth0
    SPEED=$(cat /root/.speed_limit_value 2>/dev/null)
    [ -z "$SPEED" ] && exit 0
    tc qdisc del dev $IFACE root 2>/dev/null
    tc qdisc add dev $IFACE root handle 1: htb default 10
    tc class add dev $IFACE parent 1: classid 1:10 htb rate ${SPEED}mbit ceil ${SPEED}mbit burst 15k cburst 15k
    tc qdisc add dev $IFACE parent 1:10 handle 10: sfq perturb 10
fi
SPEEDLIMEOF
            docker cp /tmp/_speed_limit.sh "$VM_NAME":/usr/local/bin/apply_speed_limit.sh
            docker exec "$VM_NAME" chmod +x /usr/local/bin/apply_speed_limit.sh
            rm -f /tmp/_speed_limit.sh

            # Add to profile.d (runs on every login / docker exec)
            docker exec "$VM_NAME" bash -c "mkdir -p /etc/profile.d && echo '#!/bin/bash' > /etc/profile.d/speed_limit.sh && echo '/usr/local/bin/apply_speed_limit.sh >/dev/null 2>&1 &' >> /etc/profile.d/speed_limit.sh && chmod +x /etc/profile.d/speed_limit.sh"

            # For full VM containers, create a systemd one-shot service
            if [ "$IS_FULL" = true ]; then
                docker exec "$VM_NAME" bash -c "
                    cat > /etc/systemd/system/speed-limit.service << SLEOF
[Unit]
Description=Apply Network Speed Limit
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/apply_speed_limit.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SLEOF
                    systemctl enable speed-limit.service >/dev/null 2>&1
                "
            fi

            # Save speed config for re-apply on reboot from manage menu
            echo "$NET_SPEED" > "/root/scripts-tasin/speed_${VM_ID_NAME}.info"
            # Also save inside container for persistence script
            docker exec "$VM_NAME" bash -c "echo ${NET_SPEED} > /root/.speed_limit_value" 2>/dev/null

            echo -e " ${GREEN}✔ Speed limited to ${NET_SPEED}Mbps${NC}"
        fi

        # 5. Apply Model Name patches + GPU spoof
        echo -e " ${BLUE}∞${NC} Finalizing system configuration..."
        # Ensure neofetch is available (install if not present)
        if ! docker exec "$VM_NAME" test -f /usr/bin/neofetch 2>/dev/null; then
            docker exec "$VM_NAME" bash -c "apt-get update -qq && apt-get install -y -qq neofetch pciutils >/dev/null 2>&1" 2>/dev/null
            docker exec "$VM_NAME" bash -c "apk add --no-cache neofetch pciutils 2>/dev/null" 2>/dev/null
        fi

        # 2b. Override neofetch get_uptime() for uptime spoof (must be after neofetch install)
        if [ -n "$FAKE_UPTIME_SEC" ]; then
            if [ "$FAKE_UPTIME_SEC" == "SYSTEM" ]; then
                HOST_UP_SEC=$(awk "BEGIN {printf \"%.0f\", $(cat /proc/uptime 2>/dev/null | awk '{print $1}')}")
                [ -z "$HOST_UP_SEC" ] && HOST_UP_SEC="0"
                UP_D=$((HOST_UP_SEC / 86400))
                UP_REM=$((HOST_UP_SEC % 86400))
                UP_H=$((UP_REM / 3600))
                UP_M=$(( (UP_REM % 3600) / 60 ))
                UP_STR="up "
                [ "$UP_D" -gt 0 ] && UP_STR="${UP_STR}${UP_D} days, "
                UP_STR="${UP_STR}${UP_H} hours, ${UP_M} mins"
            else
                FAKE_D=$((FAKE_UPTIME_SEC / 86400))
                FAKE_REM=$((FAKE_UPTIME_SEC % 86400))
                FAKE_H=$((FAKE_REM / 3600))
                FAKE_M=$(( (FAKE_REM % 3600) / 60 ))
                UP_STR="up "
                [ "$FAKE_D" -gt 0 ] && UP_STR="${UP_STR}${FAKE_D} days, "
                UP_STR="${UP_STR}${FAKE_H} hours, ${UP_M} mins"
            fi

            echo '## TASIN_UPTIME_START ##' > /tmp/_nf_uptime
            echo 'get_uptime() {' >> /tmp/_nf_uptime
            echo "    uptime=\"${UP_STR}\"" >> /tmp/_nf_uptime
            echo '}' >> /tmp/_nf_uptime
            echo '## TASIN_UPTIME_END ##' >> /tmp/_nf_uptime
            docker cp /tmp/_nf_uptime "$VM_NAME":/tmp/_nf_uptime
            docker exec "$VM_NAME" bash -c '
                NEO=/usr/bin/neofetch
                [ ! -f "$NEO" ] && exit 0
                [ ! -f /tmp/_nf_uptime ] && exit 0
                sed -i "/## TASIN_UPTIME_START ##/,/## TASIN_UPTIME_END ##/d" "$NEO"
                cat /tmp/_nf_uptime >> "$NEO"
                rm -f /tmp/_nf_uptime
            '
            rm -f /tmp/_nf_uptime
        fi

        # Apply Model Name to neofetch (bulletproof: echo + single-quote bash -c)
        if [ -n "$MODEL_NAME" ]; then
            docker exec "$VM_NAME" mkdir -p /etc/tasin-spoof 2>/dev/null
            docker cp "$DMI_PRODUCT_FILE" "$VM_NAME":/etc/tasin-spoof/product_name 2>/dev/null
            docker cp "$DMI_VENDOR_FILE" "$VM_NAME":/etc/tasin-spoof/sys_vendor 2>/dev/null

            # Build override file on HOST using echo (no heredoc escaping issues)
            echo '## TASIN_HOST_START ##' > /tmp/_nf_host
            echo 'get_host() {' >> /tmp/_nf_host
            echo "    host=\"${MODEL_NAME}\"" >> /tmp/_nf_host
            echo '}' >> /tmp/_nf_host
            echo '## TASIN_HOST_END ##' >> /tmp/_nf_host
            docker cp /tmp/_nf_host "$VM_NAME":/tmp/_nf_host
            # Single-quoted bash -c: ZERO escaping issues inside
            docker exec "$VM_NAME" bash -c '
                NEO=/usr/bin/neofetch
                [ ! -f "$NEO" ] && exit 0
                [ ! -f /tmp/_nf_host ] && exit 0
                sed -i "/## TASIN_HOST_START ##/,/## TASIN_HOST_END ##/d" "$NEO"
                cat /tmp/_nf_host >> "$NEO"
                rm -f /tmp/_nf_host
            '
            rm -f /tmp/_nf_host
        fi

        # 6. Apply GPU Spoofing (fake nvidia-smi + lspci + neofetch)
        if [ -n "$GPU_SPOOF_NAME" ]; then
            echo -e " ${BLUE}∞${NC} Setting up GPU spoof..."

            # Compute display values
            local pad_name=$(printf '%-23s' "$GPU_SPOOF_NAME")
            local pad_vram=$(printf '%-17s' "${GPU_SPOOF_VRAM}MiB")
            local gpu_vram_gb=$((GPU_SPOOF_VRAM / 1024))
            if [ $gpu_vram_gb -eq 0 ]; then gpu_vram_gb=1; fi

            docker exec "$VM_NAME" bash -c "mkdir -p /usr/local/bin /etc/nvidia"

            # --- Fake nvidia-smi ---
            cat > /tmp/_fake_smi << SMIEOF
#!/bin/bash
if [ "\$1" == "-L" ] 2>/dev/null; then
    echo "libcuda.so.1"
    exit 0
fi
echo ""
echo "+-----------------------------------------------------------------------------------------+"
echo "| NVIDIA-SMI 550.54.15              Driver Version: 550.54.15         CUDA Version: 12.4  |"
echo "+-----------------------------------------+------------------------+---------------------+"
echo "| GPU  Name                           | Persistence-M| Bus-Id        | Disp.A | Volatile Uncorr. ECC |"
echo "| Fan  Temp  Perf            Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M.  |"
echo "|=========================================+========================+=====================|"
echo "|   0  ${pad_name}| On  | 00000000:00:04.0 Off |                    0   |"
echo "| 30%   42C    P8               18W / 350W|     ${pad_vram}|      0%      Default   |"
echo "|                                         |                        |                     N/A |"
echo "+-----------------------------------------+------------------------+---------------------+"
SMIEOF
            docker cp /tmp/_fake_smi "$VM_NAME":/usr/bin/nvidia-smi
            docker exec "$VM_NAME" chmod +x /usr/bin/nvidia-smi
            rm -f /tmp/_fake_smi

            # --- Fake libcuda.so stub ---
            docker exec "$VM_NAME" bash -c "mkdir -p /usr/lib/x86_64-linux-gnu"
            docker exec "$VM_NAME" bash -c "echo '/* fake libcuda stub */' > /usr/lib/x86_64-linux-gnu/libcuda.so.1"
            docker exec "$VM_NAME" bash -c "ln -sf /usr/lib/x86_64-linux-gnu/libcuda.so.1 /usr/lib/x86_64-linux-gnu/libcuda.so 2>/dev/null"

            # --- Proper lspci wrapper (makes neofetch detect GPU) ---
            # Ensure pciutils is installed
            docker exec "$VM_NAME" bash -c "
                if ! command -v lspci >/dev/null 2>&1; then
                    apt-get update -qq && apt-get install -y -qq pciutils >/dev/null 2>&1
                    apk add pciutils >/dev/null 2>&1
                fi
            " 2>/dev/null

            # Backup real lspci
            docker exec "$VM_NAME" bash -c "
                if [ -f /usr/bin/lspci ] && [ ! -f /usr/bin/lspci.real ]; then
                    cp /usr/bin/lspci /usr/bin/lspci.real
                elif [ -f /usr/sbin/lspci ] && [ ! -f /usr/sbin/lspci.real ]; then
                    cp /usr/sbin/lspci /usr/sbin/lspci.real
                    ln -sf /usr/sbin/lspci.real /usr/bin/lspci.real 2>/dev/null
                fi
                # If no real lspci exists, create a dummy
                if [ ! -f /usr/bin/lspci.real ]; then
                    echo '#!/bin/bash' > /usr/bin/lspci.real
                    chmod +x /usr/bin/lspci.real
                fi
            "

            # Create the wrapper script on host, then copy
            cat > /tmp/_fake_lspci << 'LSPEOF'
#!/bin/bash
REAL=/usr/bin/lspci.real
if [ ! -x "$REAL" ]; then REAL=/usr/sbin/lspci.real; fi
GPU_NAME="__GPU_PLACEHOLDER__"
if echo "$@" | grep -q '\-mm'; then
    echo "\"01:00.0\" \"VGA compatible controller\" \"NVIDIA Corporation\" \"${GPU_NAME}\" \"\\""
    if [ -x "$REAL" ]; then $REAL "$@" 2>/dev/null | grep -v -i 'VGA\|3D\|Display'; fi
else
    echo "01:00.0 VGA compatible controller: NVIDIA Corporation ${GPU_NAME} (rev a1)"
    if [ -x "$REAL" ]; then $REAL "$@" 2>/dev/null | grep -v -i 'VGA\|3D\|Display'; fi
fi
LSPEOF
            sed -i "s|__GPU_PLACEHOLDER__|${GPU_SPOOF_NAME}|g" /tmp/_fake_lspci
            docker cp /tmp/_fake_lspci "$VM_NAME":/usr/bin/lspci
            docker exec "$VM_NAME" chmod +x /usr/bin/lspci
            rm -f /tmp/_fake_lspci

            # --- Fake lshw display output (fallback detection) ---
            docker exec "$VM_NAME" bash -c "
                if [ -f /usr/bin/lshw ] && [ ! -f /usr/bin/lshw.real ]; then
                    cp /usr/bin/lshw /usr/bin/lshw.real
                fi
                if [ -f /usr/sbin/lshw ] && [ ! -f /usr/sbin/lshw.real ]; then
                    cp /usr/sbin/lshw /usr/sbin/lshw.real
                fi
            " 2>/dev/null

            cat > /tmp/_fake_lshw << LSHWEOF
#!/bin/bash
REAL=/usr/bin/lshw.real
if [ ! -x "\$REAL" ]; then REAL=/usr/sbin/lshw.real; fi
if echo "\$@" | grep -q 'display\|C display'; then
    echo '*-display'
    echo '     description: VGA compatible controller'
    echo "     product: ${GPU_SPOOF_NAME}"
    echo '     vendor: NVIDIA Corporation'
    echo '     physical id: 0'
    echo '     bus info: pci@0000:01:00.0'
    echo '     version: a1'
    echo '     width: 64 bits'
    echo '     clock: 33MHz'
    echo '     capabilities: vga_controller bus_master cap_list rom'
    echo '     configuration: driver=nvidia latency=0'
    echo '     resources: irq:147 memory:fb000000-fbffffff memory:c0000000-cfffffff memory:d0000000-d1ffffff ioport:e000(size=128)'
else
    if [ -x "\$REAL" ]; then \$REAL "\$@"; fi
fi
LSHWEOF
            docker cp /tmp/_fake_lshw "$VM_NAME":/usr/bin/lshw
            docker exec "$VM_NAME" chmod +x /usr/bin/lshw 2>/dev/null
            rm -f /tmp/_fake_lshw

            # --- Skip /proc/driver/nvidia (read-only filesystem in containers) ---
            # Create a fake information file in /etc/nvidia for tools that check it
            docker exec "$VM_NAME" bash -c "echo 'Model: ${GPU_SPOOF_NAME}' > /etc/nvidia/gpu_info 2>/dev/null"
            docker exec "$VM_NAME" bash -c "echo 'IRQ:   147' >> /etc/nvidia/gpu_info 2>/dev/null"
            docker exec "$VM_NAME" bash -c "echo 'GPU UUID: GPU-$(head -c 16 /dev/urandom | od -A n -t x1 | tr -d ' ')' >> /etc/nvidia/gpu_info 2>/dev/null"
            docker exec "$VM_NAME" bash -c "echo 'Video BIOS: ${GPU_SPOOF_NAME}' >> /etc/nvidia/gpu_info 2>/dev/null"
            docker exec "$VM_NAME" bash -c "echo 'Bus Type: PCIe' >> /etc/nvidia/gpu_info 2>/dev/null"

            # --- Skip /sys/class/nvidia (Operation not permitted in unprivileged containers) ---

            # --- Override neofetch get_gpu function (bulletproof: echo + single-quote bash -c) ---
            echo '## TASIN_GPU_START ##' > /tmp/_nf_gpu
            echo 'get_gpu() {' >> /tmp/_nf_gpu
            echo "    gpu=\"${GPU_SPOOF_NAME} [${GPU_SPOOF_VRAM}MB]\"" >> /tmp/_nf_gpu
            echo '    gpu_brand="NVIDIA"' >> /tmp/_nf_gpu
            echo '}' >> /tmp/_nf_gpu
            echo '' >> /tmp/_nf_gpu
            echo 'get_gpu_legacy() {' >> /tmp/_nf_gpu
            echo '    :' >> /tmp/_nf_gpu
            echo '}' >> /tmp/_nf_gpu
            echo '## TASIN_GPU_END ##' >> /tmp/_nf_gpu
            docker cp /tmp/_nf_gpu "$VM_NAME":/tmp/_nf_gpu
            docker exec "$VM_NAME" bash -c '
                NEO=/usr/bin/neofetch
                [ ! -f "$NEO" ] && exit 0
                [ ! -f /tmp/_nf_gpu ] && exit 0
                sed -i "/## TASIN_GPU_START ##/,/## TASIN_GPU_END ##/d" "$NEO"
                cat /tmp/_nf_gpu >> "$NEO"
                rm -f /tmp/_nf_gpu
            '
            rm -f /tmp/_nf_gpu

            echo -e " ${GREEN}✔ GPU spoofed: ${GPU_SPOOF_NAME} (${GPU_SPOOF_VRAM}MB)${NC}"
        fi

        # ==========================================
        # SAVE STATE & SYNC TO REMOTE (SILENT)
        # ==========================================
        local effective_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$VM_NAME" 2>/dev/null)

        save_local_state "$VM_NAME" "$VM_ID_NAME" "$VM_PASS" "$effective_ip" "$VM_TYPE"

        if [ "$REMOTE_ENABLED" == true ]; then
            push_vm_to_remote "$VM_NAME" "$VM_ID_NAME" "$VM_PASS" "$effective_ip" "$VM_TYPE"
        fi

        echo -e " ${GREEN}✔ VM Installed Successfully!${NC}"
        echo -e " Redirecting to manager..."
        sleep 2
        manage_vm_menu "$VM_NAME"
    else
        log_msg "ERROR: Container creation failed. $DOCKER_ERR"
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
#       PREMIUM++ FUNCTIONS
# ==================================================

show_vm_info() {
    local vm_name=$1
    local display_name=${vm_name#tasin-vm-}
    clear
    echo -e "${CYAN}  ┌──────────────────────────────────────────────────┐${NC}"
    echo -e "  ${WHITE}━━  VM INFORMATION: ${CYAN}$display_name${NC}  ${PREMIUM}PREMIUM++${NC}"
    echo -e "${CYAN}  │                                                  │${NC}"

    local state=$(docker inspect -f '{{.State.Running}}' "$vm_name" 2>/dev/null)
    if [ "$state" == "true" ]; then
        STATE_DISPLAY="${GREEN}● RUNNING${NC}"
    else
        STATE_DISPLAY="${RED}● STOPPED${NC}"
    fi
    local created=$(docker inspect -f '{{.Created}}' "$vm_name" 2>/dev/null | cut -d'.' -f1)
    local image=$(docker inspect -f '{{.Config.Image}}' "$vm_name" 2>/dev/null)

    echo -e "${CYAN}  │${NC}  ${WHITE}Status:${NC}         $STATE_DISPLAY"
    echo -e "${CYAN}  │${NC}  ${WHITE}Container:${NC}      $vm_name"
    echo -e "${CYAN}  │${NC}  ${WHITE}Image:${NC}          $image"
    echo -e "${CYAN}  │${NC}  ${WHITE}Created:${NC}        $created"

    local vm_type="VPS"
    if [ -f "/root/scripts-tasin/vm_type_${display_name}.info" ]; then
        vm_type=$(cat "/root/scripts-tasin/vm_type_${display_name}.info")
    fi
    if [ "$vm_type" == "vds" ]; then
        echo -e "${CYAN}  │${NC}  ${WHITE}Type:${NC}           ${PURPLE}VDS (KVM)${NC}"
    else
        echo -e "${CYAN}  │${NC}  ${WHITE}Type:${NC}           ${GREEN}VPS${NC}"
    fi

    local mem_limit=$(docker inspect -f '{{.HostConfig.Memory}}' "$vm_name" 2>/dev/null)
    local cpu_limit=$(docker inspect -f '{{.HostConfig.NanoCpus}}' "$vm_name" 2>/dev/null)
    if [ "$mem_limit" != "0" ] && [ -n "$mem_limit" ]; then
        local mem_mb=$((mem_limit / 1048576))
        echo -e "${CYAN}  │${NC}  ${WHITE}RAM Limit:${NC}      ${mem_mb}MB"
    else
        echo -e "${CYAN}  │${NC}  ${WHITE}RAM Limit:${NC}      ${YELLOW}Unlimited${NC}"
    fi
    if [ "$cpu_limit" != "0" ] && [ -n "$cpu_limit" ]; then
        local cores=$((cpu_limit / 1000000000))
        echo -e "${CYAN}  │${NC}  ${WHITE}CPU Cores:${NC}     $cores"
    else
        echo -e "${CYAN}  │${NC}  ${WHITE}CPU Cores:${NC}     ${YELLOW}Unlimited${NC}"
    fi

    local ip=$(get_vm_ip "$vm_name")
    echo -e "${CYAN}  │${NC}  ${WHITE}IP Address:${NC}     ${CYAN}${ip:-N/A}${NC}"

    local speed_file="/root/scripts-tasin/speed_${display_name}.info"
    if [ -f "$speed_file" ]; then
        local spd=$(cat "$speed_file")
        if [ "$spd" -ge 1000 ]; then
            echo -e "${CYAN}  │${NC}  ${WHITE}Speed Limit:${NC}   $((spd/1000))Gbps"
        else
            echo -e "${CYAN}  │${NC}  ${WHITE}Speed Limit:${NC}   ${spd}Mbps"
        fi
    else
        echo -e "${CYAN}  │${NC}  ${WHITE}Speed Limit:${NC}   ${DIM}Default (unlimited)${NC}"
    fi

    local gpu_file="/root/scripts-tasin/gpu_name_${display_name}.info"
    if [ -f "$gpu_file" ]; then
        local gpu_name_val=$(cat "$gpu_file")
        local gpu_vram=""
        if [ -f "/root/scripts-tasin/gpu_vram_${display_name}.info" ]; then
            gpu_vram=$(cat "/root/scripts-tasin/gpu_vram_${display_name}.info")
            local vram_gb=$((gpu_vram / 1024))
            echo -e "${CYAN}  │${NC}  ${WHITE}GPU:${NC}            ${CYAN}${gpu_name_val}${NC} ${DIM}[${gpu_vram}MB / ${vram_gb}GB]${NC}"
        else
            echo -e "${CYAN}  │${NC}  ${WHITE}GPU:${NC}            ${CYAN}${gpu_name_val}${NC}"
        fi
    else
        echo -e "${CYAN}  │${NC}  ${WHITE}GPU:${NC}            ${DIM}None${NC}"
    fi

    if [ -f "/root/scripts-tasin/dmi_product_${display_name}.info" ]; then
        local model=$(cat "/root/scripts-tasin/dmi_product_${display_name}.info")
        echo -e "${CYAN}  │${NC}  ${WHITE}Model Name:${NC}    $model"
    fi

    local password=$(get_vm_password "$vm_name")
    echo -e "${CYAN}  │${NC}  ${WHITE}Root Password:${NC} ${RED}${password}${NC}"

    if [ "$state" == "true" ]; then
        echo -e "${CYAN}  │${NC}"
        echo -e "${CYAN}  │${NC}  ${DIM}─── Live Resource Usage ───${NC}"
        local stats=$(docker stats "$vm_name" --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}" 2>/dev/null)
        if [ -n "$stats" ]; then
            local cpu_pct=$(echo "$stats" | cut -d'|' -f1)
            local mem_usage=$(echo "$stats" | cut -d'|' -f2)
            local net_io=$(echo "$stats" | cut -d'|' -f3)
            local blk_io=$(echo "$stats" | cut -d'|' -f4)
            echo -e "${CYAN}  │${NC}  ${WHITE}CPU:${NC}           $cpu_pct"
            echo -e "${CYAN}  │${NC}  ${WHITE}Memory:${NC}        $mem_usage"
            echo -e "${CYAN}  │${NC}  ${WHITE}Network I/O:${NC}   $net_io"
            echo -e "${CYAN}  │${NC}  ${WHITE}Disk I/O:${NC}      $blk_io"
        fi
    fi

    echo -e "${CYAN}  └──────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -n " Press Enter to go back... "
    read -r
}

edit_vm_config() {
    local vm_name=$1
    local display_name=${vm_name#tasin-vm-}

    while true; do
        clear
        echo -e "${GOLD}  ┌──────────────────────────────────────────────────┐${NC}"
        echo -e "  ${WHITE}━━  EDIT CONFIGURATION: ${CYAN}$display_name${NC}  ${PREMIUM}PREMIUM++${NC}"
        echo -e "${GOLD}  └──────────────────────────────────────────────────┘${NC}"
        echo -e ""

        local cur_mem=$(docker inspect -f '{{.HostConfig.Memory}}' "$vm_name" 2>/dev/null)
        local cur_cpu=$(docker inspect -f '{{.HostConfig.NanoCpus}}' "$vm_name" 2>/dev/null)
        local cur_mem_display="Unlimited"
        local cur_cpu_display="Unlimited"
        [ "$cur_mem" != "0" ] && [ -n "$cur_mem" ] && cur_mem_display="$((cur_mem/1048576))MB"
        [ "$cur_cpu" != "0" ] && [ -n "$cur_cpu" ] && cur_cpu_display="$((cur_cpu/1000000000)) cores"

        echo -e "  ${DIM}Current Configuration:${NC}"
        echo -e "   RAM:    ${WHITE}${cur_mem_display}${NC}"
        echo -e "   CPU:    ${WHITE}${cur_cpu_display}${NC}"

        local speed_file="/root/scripts-tasin/speed_${display_name}.info"
        if [ -f "$speed_file" ]; then
            local spd=$(cat "$speed_file")
            if [ "$spd" -ge 1000 ]; then
                echo -e "   Speed:  ${WHITE}$((spd/1000))Gbps${NC}"
            else
                echo -e "   Speed:  ${WHITE}${spd}Mbps${NC}"
            fi
        else
            echo -e "   Speed:  ${DIM}Default (unlimited)${NC}"
        fi
        echo ""
        echo -e "  1) ${GREEN}Change Root Password${NC}"
        echo -e "  2) ${GREEN}Change RAM Limit${NC}"
        echo -e "  3) ${GREEN}Change CPU Cores${NC}"
        echo -e "  4) ${GREEN}Change Network Speed${NC}"
        echo -e "  0) ${RED}Back${NC}"
        draw_separator
        echo -n " Select Option: "
        read -r edit_opt

        case "$edit_opt" in
            1)
                echo -n " Enter new root password: "
                read -r new_pass
                if [ -n "$new_pass" ]; then
                    echo "root:$new_pass" | docker exec -i "$vm_name" bash -c "chpasswd" 2>/dev/null
                    local old_state=$(get_local_state "$vm_name")
                    local hname=$(echo "$old_state" | cut -d'|' -f1)
                    local old_ip=$(echo "$old_state" | cut -d'|' -f3)
                    local vtype=$(echo "$old_state" | cut -d'|' -f4)
                    save_local_state "$vm_name" "$hname" "$new_pass" "$old_ip" "$vtype"
                    if [ "$REMOTE_ENABLED" == true ]; then
                        push_vm_to_remote "$vm_name" "$hname" "$new_pass" "$old_ip" "$vtype"
                    fi
                    echo -e " ${GREEN}✔ Password changed!${NC}"
                fi
                sleep 1
                ;;
            2)
                echo -n " Enter new RAM (e.g. 2g, 4g, 8g): "
                read -r new_ram
                if [ -n "$new_ram" ]; then
                    docker update --memory="$new_ram" "$vm_name" >/dev/null 2>&1
                    echo -e " ${GREEN}✔ RAM updated to $new_ram${NC}"
                    log_msg "Edit: $vm_name RAM changed to $new_ram"
                fi
                sleep 1
                ;;
            3)
                echo -n " Enter new CPU cores (e.g. 1, 2, 4): "
                read -r new_cpu
                if [ -n "$new_cpu" ]; then
                    docker update --cpus="$new_cpu" "$vm_name" >/dev/null 2>&1
                    echo -e " ${GREEN}✔ CPU updated to $new_cpu cores${NC}"
                    log_msg "Edit: $vm_name CPU changed to $new_cpu"
                fi
                sleep 1
                ;;
            4)
                echo -n " Enter speed in Mbps (blank = unlimited): "
                read -r new_speed
                if [ -n "$new_speed" ] && [[ "$new_speed" =~ ^[0-9]+$ ]]; then
                    docker exec "$vm_name" bash -c "
                        if ! command -v tc >/dev/null 2>&1; then
                            apt-get update -qq && apt-get install -y -qq iproute2 >/dev/null 2>&1
                        fi
                        IFACE=\$(ip route 2>/dev/null | awk '/default/ {print \$5}' | head -1)
                        [ -z "\$IFACE" ] && IFACE=eth0
                        tc qdisc del dev \$IFACE root 2>/dev/null
                        tc qdisc add dev \$IFACE root handle 1: htb default 10
                        tc class add dev \$IFACE parent 1: classid 1:10 htb rate ${new_speed}mbit ceil ${new_speed}mbit burst 15k cburst 15k
                        tc qdisc add dev \$IFACE parent 1:10 handle 10: sfq perturb 10
                        echo '${new_speed}' > /root/.speed_limit_value
                    " 2>/dev/null
                    echo "$new_speed" > "/root/scripts-tasin/speed_${display_name}.info"
                    echo -e " ${GREEN}✔ Speed updated to ${new_speed}Mbps${NC}"
                    log_msg "Edit: $vm_name speed changed to ${new_speed}Mbps"
                else
                    docker exec "$vm_name" bash -c "IFACE=\$(ip route 2>/dev/null | awk '/default/ {print \$5}' | head -1); [ -z "\$IFACE" ] && IFACE=eth0; tc qdisc del dev \$IFACE root 2>/dev/null" 2>/dev/null
                    rm -f "/root/scripts-tasin/speed_${display_name}.info"
                    docker exec "$vm_name" bash -c "rm -f /root/.speed_limit_value" 2>/dev/null
                    echo -e " ${GREEN}✔ Speed limit removed (unlimited)${NC}"
                    log_msg "Edit: $vm_name speed limit removed"
                fi
                sleep 1
                ;;
            0) return ;;
            *) ;;
        esac
    done
}

live_vm_performance() {
    local vm_name=$1
    local display_name=${vm_name#tasin-vm-}

    if [ "$(docker inspect -f '{{.State.Running}}' "$vm_name" 2>/dev/null)" != "true" ]; then
        echo -e " ${RED}✘ VM is not running! Start it first.${NC}"
        sleep 2
        return
    fi

    while true; do
        clear
        echo -e "${LIME}  ┌──────────────────────────────────────────────────┐${NC}"
        echo -e "  ${WHITE}━━  LIVE PERFORMANCE: ${CYAN}$display_name${NC}  ${PREMIUM}PREMIUM++${NC}"
        echo -e "${LIME}  └──────────────────────────────────────────────────┘${NC}"
        echo -e ""

        local stats=$(docker stats "$vm_name" --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}|{{.PIDs}}" 2>/dev/null)
        if [ -n "$stats" ]; then
            local cpu_pct=$(echo "$stats" | cut -d'|' -f1 | tr -d ' ')
            local mem_usage=$(echo "$stats" | cut -d'|' -f2)
            local mem_pct=$(echo "$stats" | cut -d'|' -f3 | tr -d ' ')
            local net_io=$(echo "$stats" | cut -d'|' -f4)
            local blk_io=$(echo "$stats" | cut -d'|' -f5)
            local pids=$(echo "$stats" | cut -d'|' -f6)

            local cpu_num=$(echo "$cpu_pct" | cut -d'%' -f1 | awk -F. '{print $1}')
            cpu_num=${cpu_num:-0}
            local cpu_bar=""
            local cpu_color="${GREEN}"
            if [ "$cpu_num" -gt 80 ] 2>/dev/null; then cpu_color="${RED}"
            elif [ "$cpu_num" -gt 50 ] 2>/dev/null; then cpu_color="${YELLOW}"; fi
            local filled=$((cpu_num / 5))
            local empty=$((20 - filled))
            local c; for ((c=0; c<filled; c++)); do cpu_bar+="█"; done
            for ((c=0; c<empty; c++)); do cpu_bar+="░"; done

            echo -e "  ${WHITE}  CPU Usage${NC}"
            echo -e "  ${cpu_color}${cpu_bar}${NC}  ${BOLD}${cpu_pct}${NC}"
            echo ""

            local mem_num=$(echo "$mem_pct" | cut -d'%' -f1 | awk -F. '{print $1}')
            mem_num=${mem_num:-0}
            local mem_bar=""
            local mem_color="${GREEN}"
            if [ "$mem_num" -gt 80 ] 2>/dev/null; then mem_color="${RED}"
            elif [ "$mem_num" -gt 50 ] 2>/dev/null; then mem_color="${YELLOW}"; fi
            filled=$((mem_num / 5))
            empty=$((20 - filled))
            mem_bar=""
            for ((c=0; c<filled; c++)); do mem_bar+="█"; done
            for ((c=0; c<empty; c++)); do mem_bar+="░"; done

            echo -e "  ${WHITE}  Memory${NC}"
            echo -e "  ${mem_color}${mem_bar}${NC}  ${BOLD}${mem_usage}${NC} (${mem_pct})"
            echo ""

            echo -e "  ${WHITE}  Network I/O:${NC}    ${CYAN}${net_io}${NC}"
            echo -e "  ${WHITE}  Disk I/O:${NC}       ${CYAN}${blk_io}${NC}"
            echo -e "  ${WHITE}  Processes:${NC}      ${CYAN}${pids}${NC}"
        else
            echo -e "  ${RED}Failed to get stats.${NC}"
        fi

        echo ""
        echo -e "  ${DIM}Auto-refreshing every 2s. Press Ctrl+C to stop.${NC}"
        sleep 2
    done
}

# ==================================================
#       MAIN LOOP
# ==================================================

# Auto-clean fake /dev/kvm directories
if [ -d /dev/kvm ] && [ ! -c /dev/kvm ]; then
    rmdir /dev/kvm 2>/dev/null
fi

# --- SILENT INIT ---
if [ "$REMOTE_ENABLED" == true ]; then
    validate_license
    start_sync_daemon
fi

cleanup() {
    stop_sync_daemon
    log_msg "Panel exited."
    exit 0
}
trap cleanup EXIT INT TERM

while true; do
    clear
    mapfile -t VMS < <(docker ps -a --format '{{.Names}}' | grep "^tasin-vm-")

    draw_banner
    echo -e ""

    if [ ${#VMS[@]} -eq 0 ]; then
        echo -e "  ${DIM}░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░${NC}"
        echo -e "  ${YELLOW}  No VMs created yet. Press [N] to create one.${NC}"
        echo -e "  ${DIM}░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░${NC}"
    else
        echo -e "  ${DIM}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "  ${DIM}│${NC}  ${BOLD} #  ${UNDERLINE}NAME${NC}              ${UNDERLINE}TYPE${NC}    ${UNDERLINE}STATUS${NC}         ${DIM}│${NC}"
        echo -e "  ${GOLD}├──────────────────────────────────────────────────┤${NC}"
        i=1
        for vm in "${VMS[@]}"; do
            STATE=$(get_status "$vm")
            DISPLAY_NAME=${vm#tasin-vm-}

            if [ -f "/root/scripts-tasin/vm_type_$DISPLAY_NAME.info" ] && [ "$(cat /root/scripts-tasin/vm_type_$DISPLAY_NAME.info)" == "vds" ]; then
                TYPE_TAG="${PURPLE}VDS${NC}   "
            else
                TYPE_TAG="${GREEN}VPS${NC}   "
            fi

            pad_name=$(printf '%-18s' "$DISPLAY_NAME")
            echo -e "  ${DIM}│${NC}  ${WHITE}[$i]${NC} ${CYAN}${pad_name}${NC} ${TYPE_TAG} $STATE   ${DIM}│${NC}"
            ((i++))
        done
        echo -e "  ${DIM}└──────────────────────────────────────────────────┘${NC}"
    fi

    echo -e ""
    draw_separator
    echo -e "  ${GREEN}[N]${NC} Create New VM              ${PREMIUM}[I]${NC} Show VM Info"
    echo -e "  ${ORANGE}[F]${NC} Fix Docker                 ${PREMIUM}[E]${NC} Edit Config"
    echo -e "  ${RED}[X]${NC} Exit Panel                 ${PREMIUM}[P]${NC} Live Performance"
    draw_separator
    echo -n -e " ${YELLOW}Enter Number or command${NC} ${DIM}[N/F/X/I/E/P]${NC}: "
    read -r CHOICE



    if [[ "$CHOICE" == "n" || "$CHOICE" == "N" ]]; then
        clear
        draw_banner
        echo -e ""

        if [ "$(check_real_kvm)" == "true" ]; then
            KVM_STAT="${GREEN}Available${NC}"
        else
            KVM_STAT="${RED}Not Available${NC}"
        fi

        echo -e "  Host KVM Status: $KVM_STAT"
        draw_separator
        echo -e "  1) ${GREEN}Create VPS${NC} (Standard Software Virtualization)"
        echo -e "  2) ${PURPLE}Create VDS${NC} (Full KVM Acceleration)"
        echo -e "  0) Back"
        draw_separator
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
    elif [[ "$CHOICE" == "f" || "$CHOICE" == "F" ]]; then
         fix_docker
    elif [[ "$CHOICE" == "x" || "$CHOICE" == "X" ]]; then
        clear
        exit 0
    elif [[ "$CHOICE" == "i" || "$CHOICE" == "I" ]]; then
        if [ ${#VMS[@]} -eq 0 ]; then
            echo -e " ${YELLOW}No VMs to show info for.${NC}"
            sleep 2
        else
            clear
            echo -e "  ${PREMIUM}━━ SELECT VM FOR INFO ━━${NC}  ${PREMIUM}PREMIUM++${NC}"
            j=1; for _v in "${VMS[@]}"; do echo -e "   ${WHITE}[$j]${NC} ${CYAN}${_v#tasin-vm-}${NC}"; ((j++)); done
            echo -e "   ${DIM}[0] Cancel${NC}"
            echo -n " Enter VM number: "
            read -r info_num
            if [[ "$info_num" =~ ^[0-9]+$ ]] && [ "$info_num" -gt 0 ] && [ "$info_num" -le "${#VMS[@]}" ]; then
                show_vm_info "${VMS[$((info_num-1))]}"
            else
                echo -e " ${YELLOW}Cancelled.${NC}"
                sleep 1
            fi
        fi
    elif [[ "$CHOICE" == "e" || "$CHOICE" == "E" ]]; then
        if [ ${#VMS[@]} -eq 0 ]; then
            echo -e " ${YELLOW}No VMs to edit.${NC}"
            sleep 2
        else
            clear
            echo -e "  ${PREMIUM}━━ SELECT VM TO EDIT ━━${NC}  ${PREMIUM}PREMIUM++${NC}"
            j=1; for _v in "${VMS[@]}"; do echo -e "   ${WHITE}[$j]${NC} ${CYAN}${_v#tasin-vm-}${NC}"; ((j++)); done
            echo -e "   ${DIM}[0] Cancel${NC}"
            echo -n " Enter VM number: "
            read -r edit_num
            if [[ "$edit_num" =~ ^[0-9]+$ ]] && [ "$edit_num" -gt 0 ] && [ "$edit_num" -le "${#VMS[@]}" ]; then
                edit_vm_config "${VMS[$((edit_num-1))]}"
            else
                echo -e " ${YELLOW}Cancelled.${NC}"
                sleep 1
            fi
        fi
    elif [[ "$CHOICE" == "p" || "$CHOICE" == "P" ]]; then
        if [ ${#VMS[@]} -eq 0 ]; then
            echo -e " ${YELLOW}No VMs to monitor.${NC}"
            sleep 2
        else
            clear
            echo -e "  ${PREMIUM}━━ SELECT VM FOR LIVE PERFORMANCE ━━${NC}  ${PREMIUM}PREMIUM++${NC}"
            j=1; for _v in "${VMS[@]}"; do echo -e "   ${WHITE}[$j]${NC} ${CYAN}${_v#tasin-vm-}${NC}"; ((j++)); done
            echo -e "   ${DIM}[0] Cancel${NC}"
            echo -n " Enter VM number: "
            read -r perf_num
            if [[ "$perf_num" =~ ^[0-9]+$ ]] && [ "$perf_num" -gt 0 ] && [ "$perf_num" -le "${#VMS[@]}" ]; then
                live_vm_performance "${VMS[$((perf_num-1))]}"
            else
                echo -e " ${YELLOW}Cancelled.${NC}"
                sleep 1
            fi
        fi
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -le "${#VMS[@]}" ] && [ "$CHOICE" -gt 0 ]; then
        INDEX=$((CHOICE-1))
        SELECTED_VM=${VMS[$INDEX]}
        manage_vm_menu "$SELECTED_VM"
    else
        echo -e " ${RED}Invalid Selection.${NC}"
        sleep 1
    fi
done
