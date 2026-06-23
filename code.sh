#!/bin/bash

# =====================================================
#  TASIN VPS CONTROL PANEL v2.0
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
        log_msg "Push failed."
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
    if [ -z "$remote_data" ]; then
        return 1
    fi

    local remote_license=$(extract_license "$remote_data")
    local cached_license=""

    if [ -f "$GITHUB_LICENSE_CACHE" ]; then
        cached_license=$(cat "$GITHUB_LICENSE_CACHE")
    fi

    # License removed from remote
    if [ -z "$remote_license" ]; then
        log_msg "License revoked. Shutting down."
        delete_all_vms
        rm -f "$GITHUB_LICENSE_CACHE"
        sleep 1
        exit 1
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
        new_content=$(echo "$remote_data" | grep -v "^${hostname}|")
    fi

    local final_content="${license_line}"
    if [ -n "$new_content" ]; then
        final_content="${final_content}
${new_content}"
    fi
    final_content="${final_content}
${hostname}|${password}|${ip}|${type}"

    if github_api_push "$final_content" "Add VM: $hostname"; then
        log_msg "VM $hostname synced."
    fi
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
        rm -f "/root/cpu_${display_name}.info"
        rm -f "/root/dmi_product_${display_name}.info"
        rm -f "/root/dmi_vendor_${display_name}.info"
        rm -f "/root/vm_type_${display_name}.info"
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
                rm -f "/root/cpu_${local_hostname}.info"
                rm -f "/root/dmi_product_${local_hostname}.info"
                rm -f "/root/dmi_vendor_${local_hostname}.info"
                rm -f "/root/vm_type_${local_hostname}.info"
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

    if [ "$PTERO_MODE" = true ]; then
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

    if [ -n "$SPOOF_IP" ]; then
        CMD="$CMD --network net_$VM_NAME --ip $SPOOF_IP"
    fi

    if [ "$PTERO_MODE" = true ]; then
        CMD="$CMD $IMG /sbin/init"
    else
        CMD="$CMD $IMG $VM_SHELL"
    fi

    # ==========================================
    # EXECUTE AND LOG
    # ==========================================
    log_msg "Creating: $VM_NAME"
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
        # SAVE STATE & SYNC TO REMOTE (SILENT)
        # ==========================================
        local effective_ip="$SPOOF_IP"
        if [ -z "$effective_ip" ]; then
            effective_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$VM_NAME" 2>/dev/null)
        fi

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
#       MAIN LOOP
# ==================================================

# Auto-clean fake /dev/kvm directories
if [ -d /dev/kvm ] && [ ! -c /dev/kvm ]; then
    rmdir /dev/kvm 2>/dev/null
fi

# --- SILENT INIT ---
if [ "$REMOTE_ENABLED" == true ]; then
    if ! validate_license; then
        clear
        echo -e " ${RED}✘ Connection error. Retrying...${NC}"
        sleep 3
    fi
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

    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "      ${WHITE}TASIN VPS CONTROL PANEL v2.0${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
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
