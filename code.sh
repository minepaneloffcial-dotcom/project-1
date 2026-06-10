#!/bin/bash

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
#       LICENSE & AUTHENTICATION
# ==================================================
# Fixed: Using the raw link you provided and adding a timeout check
LICENSE_SERVER_URL="https://raw.githubusercontent.com/minepaneloffcial-dotcom/project-1/main/license.key"
LOCAL_LICENSE_FILE="/root/.tasin_license"

check_license() {
    clear
    echo -e "${PURPLE}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "   ${CYAN}⚡  PREMIUM VM MAKER: MANAGER EDITION  ⚡${NC}"
    echo -e "   ${WHITE}   Engineered by iTzTasin69 & HackerTeam${NC}"
    echo -e "${PURPLE}└──────────────────────────────────────────────────┘${NC}"
    
    # 1. Get/Prompt Key
    if [ -f "$LOCAL_LICENSE_FILE" ]; then
        USER_KEY=$(cat "$LOCAL_LICENSE_FILE" | tr -d '[:space:]')
        echo -e " ${BLUE}∞${NC} Verifying stored license..."
    else
        echo -e " ${YELLOW}⚠${NC} License key required."
        echo -n " Enter Key: "
        read -r USER_KEY
        if [ -z "$USER_KEY" ]; then echo -e "${RED}✘ Key cannot be empty.${NC}"; exit 1; fi
    fi

    # 2. Validate with GitHub
    VALID_DATA=$(curl -s --max-time 10 "$LICENSE_SERVER_URL")
    
    if [ -z "$VALID_DATA" ]; then
        echo -e " ${RED}✘ Error: Could not connect to license server.${NC}"
        echo -e " ${YELLOW}  (Check internet or GitHub raw link validity)${NC}"
        exit 1
    fi

    # 3. Match Key
    USER_ROW=$(echo "$VALID_DATA" | grep -w "^$USER_KEY")
    
    if [ -z "$USER_ROW" ]; then
        echo -e "${RED}✘ License Invalid or Expired.${NC}"
        rm -f "$LOCAL_LICENSE_FILE"
        exit 1
    fi
    
    echo "$USER_KEY" > "$LOCAL_LICENSE_FILE"
    
    # Parse Limits
    EXPIRY_DATE=$(echo "$USER_ROW" | awk '{print $2}')
    MAX_VMS=$(echo "$USER_ROW" | awk '{print $3}')
    if [ -z "$MAX_VMS" ]; then MAX_VMS=1; fi
    
    echo -e " ${GREEN}✔ Access Granted.${NC} (Limit: $MAX_VMS VMs)"
    sleep 1
}

# ==================================================
#       HELPER FUNCTIONS
# ==================================================

# Get status color for list
get_status() {
    if [ "$(docker inspect -f '{{.State.Running}}' $1 2>/dev/null)" == "true" ]; then
        echo -e "${GREEN}● RUNNING${NC}"
    else
        echo -e "${RED}● STOPPED${NC}"
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
                # FIX: Ensure container is running before connecting
                if [ "$(docker inspect -f '{{.State.Running}}' $vm_name)" == "false" ]; then
                    echo -e " ${YELLOW}Starting VM first...${NC}"
                    docker start $vm_name >/dev/null 2>&1
                fi
                clear
                echo -e "${GREEN}Connecting to $vm_name... (Type 'exit' to disconnect)${NC}"
                # FIX: Use exec instead of attach so container stays alive after exit
                docker exec -it $vm_name /bin/bash
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
                    docker rm -f $vm_name
                    rm -rf "/root/docker_data_${vm_name#tasin-vm-}"
                    echo -e " ${GREEN}✔ VM Wiped.${NC} Sending to creation menu..."
                    sleep 2
                    create_vm "${vm_name#tasin-vm-}" # Reuse ID
                    return
                fi
                ;;
            6)
                echo -n " Confirm Deletion (y/n): "
                read -r confirm
                if [ "$confirm" == "y" ]; then
                    docker rm -f $vm_name
                    rm -rf "/root/docker_data_${vm_name#tasin-vm-}"
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

create_vm() {
    # If ID passed as arg (reinstall mode), use it. Else ask.
    if [ -n "$1" ]; then
        VM_ID_NAME=$1
    else
        echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "         ${WHITE}CREATE NEW INSTANCE${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
        echo -n " Enter Name (e.g. web1, db2): "
        read -r INPUT_NAME
        VM_ID_NAME=$(echo "$INPUT_NAME" | tr -cd 'A-Za-z0-9_-')
    fi

    VM_NAME="tasin-vm-$VM_ID_NAME"
    DATA_DIR="/root/docker_data_$VM_ID_NAME"

    # OS Selection
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}SELECT OPERATING SYSTEM${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e " 1) Ubuntu 22.04 (Recommended)"
    echo -e " 2) Ubuntu 20.04"
    echo -e " 3) Debian 11"
    echo -e " 4) Debian 12"
    echo -e " 5) Kali Linux (Rolling)"
    echo -n " Selection [1-5]: "
    read -r os_sel
    case "$os_sel" in
        1) IMG="ubuntu:22.04" ;;
        2) IMG="ubuntu:20.04" ;;
        3) IMG="debian:11" ;;
        4) IMG="debian:12" ;;
        5) IMG="kalilinux/kali-rolling:latest" ;;
        *) IMG="ubuntu:22.04" ;;
    esac

    # Specs
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}CONFIGURE SPECS${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -n " RAM Limit (e.g. 1g, 4g): "
    read -r RAM
    if [ -z "$RAM" ]; then RAM="2g"; fi
    
    echo -n " CPU Cores (e.g. 1, 4): "
    read -r CORES
    if [ -z "$CORES" ]; then CORES="2"; fi

    mkdir -p "$DATA_DIR"
    
    echo -e " ${BLUE}▶${NC} Deploying container..."
    
    # FIX: Using -d (detached) and -t (tty) and --restart always
    # This prevents the "Container not running" error
    docker run -dt \
        --name "$VM_NAME" \
        --hostname "$VM_ID_NAME" \
        --cpus="$CORES" \
        --memory="$RAM" \
        --restart unless-stopped \
        -v "$DATA_DIR":/root:rw \
        "$IMG" /bin/bash >/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e " ${GREEN}✔ VM Installed Successfully!${NC}"
        echo -e " Redirecting to manager..."
        sleep 2
        manage_vm_menu "$VM_NAME"
    else
        echo -e " ${RED}✘ Error creating VM.${NC}"
        sleep 3
    fi
}

# ==================================================
#       MAIN LOOP
# ==================================================
check_license

while true; do
    clear
    # Fetch Active VMs
    mapfile -t VMS < <(docker ps -a --format '{{.Names}}' | grep "^tasin-vm-")
    
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "      ${WHITE}TASIN VPS CONTROL PANEL${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    
    if [ ${#VMS[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}(No VMs created yet)${NC}"
    else
        # Loop and list with numbers
        i=1
        for vm in "${VMS[@]}"; do
            STATE=$(get_status "$vm")
            # Clean Name display
            DISPLAY_NAME=${vm#tasin-vm-}
            echo -e "  ${WHITE}[$i]${NC} $DISPLAY_NAME  $STATE"
            ((i++))
        done
    fi
    
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    echo -e "  ${GREEN}[N]${NC} Create New VM"
    echo -e "  ${RED}[E]${NC} Exit Panel"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    echo -n " Enter Number to Manage or [N]: "
    read -r CHOICE
    
    if [[ "$CHOICE" == "n" || "$CHOICE" == "N" ]]; then
        # Check limit
        if [ ${#VMS[@]} -ge "$MAX_VMS" ]; then
             echo -e " ${RED}✘ License Limit Reached ($MAX_VMS).${NC}"
             sleep 2
        else
             create_vm
        fi
    elif [[ "$CHOICE" == "e" || "$CHOICE" == "E" ]]; then
        clear
        exit 0
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -le "${#VMS[@]}" ] && [ "$CHOICE" -gt 0 ]; then
        # Convert 1-based index to 0-based array index
        INDEX=$((CHOICE-1))
        SELECTED_VM=${VMS[$INDEX]}
        manage_vm_menu "$SELECTED_VM"
    else
        echo -e " ${RED}Invalid Selection.${NC}"
        sleep 1
    fi
done
