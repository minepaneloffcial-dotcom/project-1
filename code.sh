#!/bin/bash

# ==================================================
#       🎨 OLD-SCHOOL ASCII COLOR PALETTE
# ==================================================
NC='\033[0m' 
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'

LICENSE_SERVER_URL="https://githubusercontent.com"
LOCAL_LICENSE_FILE="/root/.tasin_license"

check_license() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              SYSTEM AUTHENTICATION               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ -f "$LOCAL_LICENSE_FILE" ]; then
        USER_KEY=$(cat "$LOCAL_LICENSE_FILE" | tr -d '[:space:]')
        echo -e " Checking license key status..."
    else
        echo -e " License key missing."
        echo -n " Enter your access token: "
        read -r USER_KEY
        if [ -z "$USER_KEY" ]; then echo -e "${RED} Error: Key cannot be empty.${NC}"; exit 1; fi
    fi

    VALID_DATA=$(curl -s --max-time 10 "$LICENSE_SERVER_URL")
    
    if [ -z "$VALID_DATA" ]; then
        echo -e " ${RED}Error: Server unreachable.${NC}"
        exit 1
    fi

    USER_ROW=$(echo "$VALID_DATA" | grep -w "^$USER_KEY")
    
    if [ -z "$USER_ROW" ]; then
        echo -e "${RED}Error: Invalid or expired license key.${NC}"
        rm -f "$LOCAL_LICENSE_FILE"
        exit 1
    fi
    
    echo "$USER_KEY" > "$LOCAL_LICENSE_FILE"
    MAX_VMS=$(echo "$USER_ROW" | awk '{print $3}')
    if [ -z "$MAX_VMS" ]; then MAX_VMS=1; fi
    
    echo -e " ${GREEN}License active.${NC} Authorized VPS slots: ${CYAN}$MAX_VMS${NC}"
    sleep 1
}

get_status() {
    if [ "$(docker inspect -f '{{.State.Running}}' $1 2>/dev/null)" == "true" ]; then
        echo -e "${GREEN}Running${NC}"
    else
        echo -e "${RED}Offline${NC}"
    fi
}

manage_vm_menu() {
    local vm_name=$1
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                    MANAGE VPS                    ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  VPS Name: ${WHITE}$vm_name${NC}"
        echo -e "  Status:   $(get_status $vm_name)"
        echo ""
        echo -e "  Open Terminal Console"
        echo -e "  Restart VPS"
        echo -e "  Stop VPS"
        echo -e "  Start VPS"
        echo -e "  Reinstall OS"
        echo -e "  Remove VPS"
        echo -e "  Back to Menu"
        echo ""
        echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
        echo -n " Choose option: "
        read -r action

        case "$action" in
            1)
                if [ "$(docker inspect -f '{{.State.Running}}' $vm_name)" == "false" ]; then
                    docker start $vm_name >/dev/null 2>&1
                fi
                clear
                echo -e " Connecting to terminal. Type 'exit' to disconnect."
                echo ""
                docker exec -it $vm_name /bin/bash
                ;;
            2)
                docker restart $vm_name >/dev/null 2>&1
                echo -e " ${GREEN}VPS restarted.${NC}"
                sleep 1
                ;;
            3)
                docker stop $vm_name >/dev/null 2>&1
                echo -e " ${RED}VPS stopped.${NC}"
                sleep 1
                ;;
            4)
                docker start $vm_name >/dev/null 2>&1
                echo -e " ${GREEN}VPS started.${NC}"
                sleep 1
                ;;
            5)
                echo -e " ${RED}Warning: This deletes all data inside this VPS!${NC}"
                echo -n " Are you sure? (y/n): "
                read -r confirm
                if [ "$confirm" == "y" ]; then
                    docker rm -f $vm_name >/dev/null 2>&1
                    rm -rf "/root/docker_data_${vm_name#tasin-vm-}"
                    echo -e " ${GREEN}Data cleared. Opening installer...${NC}"
                    sleep 1.5
                    create_vm "${vm_name#tasin-vm-}" 
                    return
                fi
                ;;
            6)
                echo -n " Permanently remove this VPS? (y/n): "
                read -r confirm
                if [ "$confirm" == "y" ]; then
                    docker rm -f $vm_name >/dev/null 2>&1
                    rm -rf "/root/docker_data_${vm_name#tasin-vm-}"
                    echo -e " ${GREEN}VPS removed.${NC}"
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
    if [ -n "$1" ]; then
        VM_ID_NAME=$1
    else
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                  CREATE NEW VPS                  ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -n " Enter VPS Name (e.g., node-1): "
        read -r INPUT_NAME
        VM_ID_NAME=$(echo "$INPUT_NAME" | tr -cd 'A-Za-z0-9_-')

        echo -n " Enter Root Password: "
        read -r VM_PASS
        if [ -z "$VM_PASS" ]; then VM_PASS="root"; fi
        
        echo -n " Enter VPS Host Name (e.g., Cryzon Cloud Host Ltd.): "
        read -r VM_HOST_BRAND
        if [ -z "$VM_HOST_BRAND" ]; then VM_HOST_BRAND="Cryzon Cloud Host Ltd."; fi
    fi

    VM_NAME="tasin-vm-$VM_ID_NAME"
    DATA_DIR="/root/docker_data_$VM_ID_NAME"

    # ==========================================
    # 🔥 FIX: AUTO-PURGE DEAD NAME CONFLICTS
    # ==========================================
    if [ "$(docker ps -a -q -f name=^${VM_NAME}$)" ]; then
        echo -e " ${YELLOW}Cleaning up old container conflicts...${NC}"
        docker rm -f "$VM_NAME" >/dev/null 2>&1
    fi

    # ==========================================
    # OS SELECTION MENU
    # ==========================================
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                 SELECT OS ENGINE                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Ubuntu 22.04 LTS"
    echo -e "  Ubuntu 20.04 LTS"
    echo -e "  Debian 12 (Bookworm)"
    echo -e "  Debian 11 (Bullseye)"
    echo -e "  Kali Linux"
    echo -e "  Alpine Linux (Lightweight)"
    echo ""
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo -n " Choose Operating System [1-6]: "
    read -r os_sel
    case "$os_sel" in
        1) IMG="ubuntu:22.04" ;;
        2) IMG="ubuntu:20.04" ;;
        3) IMG="debian:12" ;;
        4) IMG="debian:11" ;;
        5) IMG="kalilinux/kali-rolling:latest" ;;
        6) IMG="alpine:latest" ;;
        *) IMG="ubuntu:22.04" ;;
    esac

    # ==========================================
    # HARDWARE ALLOCATION
    # ==========================================
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║               RESOURCE ALLOCATION                ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Dedicated Mode (Strict Limits)"
    echo -e "  Shared Mode (Burstable Limits)"
    echo -e "  Unlimited Mode (Uses Host Limits)"
    echo ""
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo -n " Select Mode [1-3]: "
    read -r res_type

    RAM=""
    CORES=""
    MODE="shared"

    if [ "$res_type" == "3" ]; then
        MODE="unlimited"
    else
        echo ""
        echo -n " Enter RAM Limit (e.g., 512m, 2g, 4g): "
        read -r RAM
        if [ -z "$RAM" ]; then RAM="1g"; fi
        
        echo -n " Enter CPU Cores Limit (e.g., 1, 2, 4): "
        read -r CORES
        if [ -z "$CORES" ]; then CORES="1"; fi

        if [ "$res_type" == "1" ]; then MODE="dedicated"; else MODE="shared"; fi
    fi

    # ==========================================
    # CPU SELECTION MENU
    # ==========================================
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                 SELECT YOUR CPU                  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  AMD EPYC 9654 (96 Cores)"
    echo -e "  AMD Ryzen 9 7950X3D"
    echo -e "  Intel Core i9-14900KS"
    echo -e "  Intel Xeon Platinum 8490H"
    echo -e "  Use Real Host CPU (No Spoof)"
    echo ""
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo -n " Choose Processor Model [1-5]: "
    read -r vendor_sel

    V_ID="GenuineIntel"
    C_NAME="Intel Xeon"
    C_MHZ="2500.000"
    USE_SPOOF=true

    case "$vendor_sel" in
        1) V_ID="AuthenticAMD"; C_NAME="AMD EPYC 9654 96-Core Processor"; C_MHZ="3700.000" ;;
        2) V_ID="AuthenticAMD"; C_NAME="AMD Ryzen 9 7950X3D 16-Core Processor"; C_MHZ="5700.000" ;;
        3) V_ID="GenuineIntel"; C_NAME="Intel(R) Core(TM) i9-14900KS"; C_MHZ="6200.000" ;;
        4) V_ID="GenuineIntel"; C_NAME="Intel(R) Xeon(R) Platinum 8490H"; C_MHZ="3500.000" ;;
        5) USE_SPOOF=false ;;
        *) USE_SPOOF=false ;;
    esac

    mkdir -p "$DATA_DIR"

    # ==========================================
    # ⚙️ MULTI-TRY CAPABILITY REPAIR LOGIC
    # ==========================================
    SUCCESS=false

    # Try 1: Privileged Mode with Limits
    DOCKER_CMD="docker run -dt --name \"$VM_NAME\" --hostname \"$VM_ID_NAME\" --privileged --restart unless-stopped -v \"$DATA_DIR\":/root:rw"
    if [ -c /dev/kvm ]; then DOCKER_CMD="$DOCKER_CMD --device /dev/kvm"; fi
if [ "$MODE" != "unlimited" ]; then DOCKER_CMD="$DOCKER_CMD --cpus=\"$CORES\" --memory=\"$RAM\""; fi
DOCKER_CMD="$DOCKER_CMD \"$IMG\" /bin/bash"
eval "$DOCKER_CMD" >/dev/null 2>&1
if [ $? -eq 0 ]; then SUCCESS=true; fi

# Try 2: Standard Capability Mode
if [ "$SUCCESS" = false ]; then
    DOCKER_CMD="docker run -dt --name \"$VM_NAME\" --hostname \"$VM_ID_NAME\" --cap-add=SYS_ADMIN --restart unless-stopped -v \"$DATA_DIR\":/root:rw"
    if [ -c /dev/kvm ]; then DOCKER_CMD="$DOCKER_CMD --device /dev/kvm"; fi
    if [ "$MODE" != "unlimited" ]; then DOCKER_CMD="$DOCKER_CMD --cpus=\"$CORES\" --memory=\"$RAM\""; fi
    DOCKER_CMD="$DOCKER_CMD \"$IMG\" /bin/bash"
    eval "$DOCKER_CMD" >/dev/null 2>&1
    if [ $? -eq 0 ]; then SUCCESS=true; fi
fi

# Try 3: Safe Mode (Stripped down configs)
if [ "$SUCCESS" = false ]; then
    DOCKER_CMD="docker run -dt --name \"$VM_NAME\" --hostname \"$VM_ID_NAME\" --restart unless-stopped -v \"$DATA_DIR\":/root:rw \"$IMG\" /bin/bash"
    eval "$DOCKER_CMD" >/dev/null 2>&1
    if [ $? -eq 0 ]; then SUCCESS=true; fi
fi

if [ "$SUCCESS" = true ]; then
    docker exec "$VM_NAME" /bin/bash -c "echo 'root:$VM_PASS' | chpasswd" 2>/dev/null
    
    # Inject custom spoof signatures natively
    if [ "$USE_SPOOF" = true ]; then
        docker exec "$VM_NAME" /bin/bash -c "mkdir -p /etc/fake && cat /proc/cpuinfo | sed -e 's/^vendor_id.*/vendor_id\t: $V_ID/' -e 's/^model name.*/model name\t: $C_NAME/' -e 's/^cpu MHz.*/cpu MHz\t\t: $C_MHZ/' > /etc/fake/cpuinfo" 2>/dev/null
        docker exec "$VM_NAME" /bin/bash -c "echo 'alias cat=\"cat /etc/fake/cpuinfo #\"' >> /root/.bashrc" 2>/dev/null
        docker exec "$VM_NAME" /bin/bash -c "echo 'cat() { if [ \"\$1\" = \"/proc/cpuinfo\" ]; then command cat /etc/fake/cpuinfo; else command cat \"\$@\"; fi; }' >> /root/.bashrc" 2>/dev/null
    fi

    # Branding updates
    docker exec "$VM_NAME" /bin/bash -c "echo 'export VPS_HOST_BRAND=\"$VM_HOST_BRAND\"' >> /root/.bashrc" 2>/dev/null
    docker exec "$VM_NAME" /bin/bash -c "sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME=\"Ubuntu 22.04.5 LTS (Powered by $VM_HOST_BRAND)\"/' /etc/os-release 2>/dev/null"

    echo -e " ${GREEN}VPS created successfully.${NC}"
    sleep 1
    manage_vm_menu "$VM_NAME"
else
    echo -e " ${RED}Error: VPS creation failed. Check Docker status via systemctl status docker${NC}"
    sleep 3
fi
}

# ==================================================
#       🔄 MASTER MAIN INTERFACE LOOP
# ==================================================
check_license

while true; do
    clear
    mapfile -t VMS < <(docker ps -a --format '{{.Names}}' | grep "^tasin-vm-")
    
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              MASTER VPS CONTROLLER               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ ${#VMS[@]} -eq 0 ]; then
        echo -e "   No active VPS containers found."
    else
        i=1
        for vm in "${VMS[@]}"; do
            STATE=$(get_status "$vm")
            DISPLAY_NAME=${vm#tasin-vm-}
            echo -e "  [$i] Name: ${WHITE}$DISPLAY_NAME${NC} [Status: $STATE]"
            ((i++))
        done
    fi
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "  [N] Create VPS"
    echo -e "  [E] Exit Panel"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo -n " Enter option choice: "
    read -r CHOICE
    
    if [[ "$CHOICE" == "n" || "$CHOICE" == "N" ]]; then
        if [ ${#VMS[@]} -ge "$MAX_VMS" ]; then
             echo -e " ${RED}Error: VPS quota limit reached ($MAX_VMS max).${NC}"
             sleep 2
        else
             create_vm
        fi
    elif [[ "$CHOICE" == "e" || "$CHOICE" == "E" ]]; then
        clear
        echo -e "Exiting controller panel..."
        exit 0
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -le "${#VMS[@]}" ] && [ "$CHOICE" -gt 0 ]; then
        INDEX=$((CHOICE-1))
        SELECTED_VM=${VMS[$INDEX]}
        manage_vm_menu "$SELECTED_VM"
    else
        echo -e " ${RED}Error: Invalid selection.${NC}"
        sleep 1
    fi
done
