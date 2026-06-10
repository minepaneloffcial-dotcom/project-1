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
LICENSE_SERVER_URL="https://raw.githubusercontent.com/minepaneloffcial-dotcom/project-1/main/license.key"
LOCAL_LICENSE_FILE="/root/.tasin_license"

check_license() {
    clear
    echo -e "${PURPLE}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "   ${CYAN}⚡  PREMIUM VM MAKER: MANAGER EDITION  ⚡${NC}"
    echo -e "   ${WHITE}   Engineered by iTzTasin69 & HackerTeam${NC}"
    echo -e "${PURPLE}└──────────────────────────────────────────────────┘${NC}"
    
    if [ -f "$LOCAL_LICENSE_FILE" ]; then
        USER_KEY=$(cat "$LOCAL_LICENSE_FILE" | tr -d '[:space:]')
        echo -e " ${BLUE}∞${NC} Verifying stored license..."
    else
        echo -e " ${YELLOW}⚠${NC} License key required."
        echo -n " Enter Key: "
        read -r USER_KEY
        if [ -z "$USER_KEY" ]; then echo -e "${RED}✘ Key cannot be empty.${NC}"; exit 1; fi
    fi

    VALID_DATA=$(curl -s --max-time 10 "$LICENSE_SERVER_URL")
    
    if [ -z "$VALID_DATA" ]; then
        echo -e " ${RED}✘ Error: Could not connect to license server.${NC}"
        exit 1
    fi

    USER_ROW=$(echo "$VALID_DATA" | grep -w "^$USER_KEY")
    
    if [ -z "$USER_ROW" ]; then
        echo -e "${RED}✘ License Invalid or Expired.${NC}"
        rm -f "$LOCAL_LICENSE_FILE"
        exit 1
    fi
    
    echo "$USER_KEY" > "$LOCAL_LICENSE_FILE"
    MAX_VMS=$(echo "$USER_ROW" | awk '{print $3}')
    if [ -z "$MAX_VMS" ]; then MAX_VMS=1; fi
    
    echo -e " ${GREEN}✔ Access Granted.${NC} (Limit: $MAX_VMS VMs)"
    sleep 1
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
                    # Cleanup old files
                    docker rm -f $vm_name
                    rm -rf "/root/docker_data_${vm_name#tasin-vm-}"
                    rm -f "/root/cpu_${vm_name#tasin-vm-}.info"
                    echo -e " ${GREEN}✔ VM Wiped.${NC} Sending to creation menu..."
                    sleep 2
                    create_vm "${vm_name#tasin-vm-}" 
                    return
                fi
                ;;
            6)
                echo -n " Confirm Deletion (y/n): "
                read -r confirm
                if [ "$confirm" == "y" ]; then
                    docker rm -f $vm_name
                    rm -rf "/root/docker_data_${vm_name#tasin-vm-}"
                    rm -f "/root/cpu_${vm_name#tasin-vm-}.info"
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
    if [ -n "$1" ]; then
        VM_ID_NAME=$1
    else
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "         ${WHITE}CREATE NEW INSTANCE${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
        echo -n " Enter Name (e.g. web1, db2): "
        read -r INPUT_NAME
        VM_ID_NAME=$(echo "$INPUT_NAME" | tr -cd 'A-Za-z0-9_-')
    fi

    VM_NAME="tasin-vm-$VM_ID_NAME"
    DATA_DIR="/root/docker_data_$VM_ID_NAME"
    CPU_FILE="/root/cpu_$VM_ID_NAME.info"

    # 1. OS Selection
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}SELECT OPERATING SYSTEM${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e " 1) Ubuntu 22.04"
    echo -e " 2) Debian 11"
    echo -e " 3) Kali Linux"
    echo -n " Selection [1-3]: "
    read -r os_sel
    case "$os_sel" in
        1) IMG="ubuntu:22.04" ;;
        2) IMG="debian:11" ;;
        3) IMG="kalilinux/kali-rolling:latest" ;;
        *) IMG="ubuntu:22.04" ;;
    esac

    # 2. Hardware Specs
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}CONFIGURE HARDWARE${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -n " RAM Limit (e.g. 1g, 8g): "
    read -r RAM
    if [ -z "$RAM" ]; then RAM="2g"; fi
    
    echo -n " CPU Cores (e.g. 2, 8): "
    read -r CORES
    if [ -z "$CORES" ]; then CORES="2"; fi

    # 3. CPU CUSTOM MAKER
    clear
    echo -e "${PURPLE}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}CPU SPOOFING / CUSTOM MAKER${NC}"
    echo -e "${PURPLE}└──────────────────────────────────────────────────┘${NC}"
    echo -e " 1) Default (Host CPU)"
    echo -e " 2) Intel Core i9-14900KS (6.2GHz)"
    echo -e " 3) AMD EPYC 9654 (Data Center)"
    echo -e " 4) ${GREEN}Custom Maker (Type your own)${NC}"
    echo -n " Selection [1-4]: "
    read -r cpu_type

    # Default Values
    V_ID="GenuineIntel"
    C_NAME="Intel(R) Xeon(R) CPU"
    C_MHZ="2400.000"

    case "$cpu_type" in
        2) 
            C_NAME="Intel Core i9-14900KS"
            C_MHZ="6200.000"
            ;;
        3) 
            V_ID="AuthenticAMD"
            C_NAME="AMD EPYC 9654 96-Core Processor"
            C_MHZ="3700.000"
            ;;
        4)
            echo ""
            echo -n " Enter Vendor ID (e.g. AuthenticAMD): "
            read -r V_ID
            echo -n " Enter Model Name (e.g. NASA SuperComp): "
            read -r C_NAME
            echo -n " Enter MHz Speed (e.g. 9999.000): "
            read -r C_MHZ
            ;;
    esac

    # Generate Unique CPU File
    if [ "$cpu_type" != "1" ]; then
        sed -e "s/^vendor_id.*/vendor_id\t: $V_ID/" \
            -e "s/^model name.*/model name\t: $C_NAME/" \
            -e "s/^cpu MHz.*/cpu MHz\t\t: $C_MHZ/" \
            /proc/cpuinfo > "$CPU_FILE"
        USE_SPOOF=true
    else
        USE_SPOOF=false
    fi

    mkdir -p "$DATA_DIR"
    
    echo -e " ${BLUE}▶${NC} Deploying container..."
    
    # DOCKER RUN COMMAND
    if [ "$USE_SPOOF" = true ]; then
        docker run -dt \
            --name "$VM_NAME" \
            --hostname "$VM_ID_NAME" \
            --cpus="$CORES" \
            --memory="$RAM" \
            --restart unless-stopped \
            -v "$DATA_DIR":/root:rw \
            -v "$CPU_FILE":/proc/cpuinfo:ro \
            "$IMG" /bin/bash >/dev/null
    else
        docker run -dt \
            --name "$VM_NAME" \
            --hostname "$VM_ID_NAME" \
            --cpus="$CORES" \
            --memory="$RAM" \
            --restart unless-stopped \
            -v "$DATA_DIR":/root:rw \
            "$IMG" /bin/bash >/dev/null
    fi
    
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
    mapfile -t VMS < <(docker ps -a --format '{{.Names}}' | grep "^tasin-vm-")
    
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "      ${WHITE}TASIN VPS CONTROL PANEL${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    
    if [ ${#VMS[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}(No VMs created yet)${NC}"
    else
        i=1
        for vm in "${VMS[@]}"; do
            STATE=$(get_status "$vm")
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
        INDEX=$((CHOICE-1))
        SELECTED_VM=${VMS[$INDEX]}
        manage_vm_menu "$SELECTED_VM"
    else
        echo -e " ${RED}Invalid Selection.${NC}"
        sleep 1
    fi
done
