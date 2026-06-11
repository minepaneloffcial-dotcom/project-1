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
        # 1. Ask for Name
        echo -n " 1. Enter Hostname (e.g. web1): "
        read -r INPUT_NAME
        VM_ID_NAME=$(echo "$INPUT_NAME" | tr -cd 'A-Za-z0-9_-')

        # 2. Ask for Password
        echo -n " 2. Set Root Password: "
        read -r VM_PASS
        if [ -z "$VM_PASS" ]; then VM_PASS="root"; fi
    fi

    VM_NAME="tasin-vm-$VM_ID_NAME"
    DATA_DIR="/root/docker_data_$VM_ID_NAME"
    CPU_FILE="/root/cpu_$VM_ID_NAME.info"

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
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    echo -n " Selection [1-8]: "
    read -r os_sel
    case "$os_sel" in
        1) IMG="ubuntu:22.04" ;;
        2) IMG="ubuntu:20.04" ;;
        3) IMG="ubuntu:18.04" ;;
        4) IMG="debian:12" ;;
        5) IMG="debian:11" ;;
        6) IMG="debian:10" ;;
        7) IMG="kalilinux/kali-rolling:latest" ;;
        8) IMG="alpine:latest" ;;
        *) IMG="ubuntu:22.04" ;;
    esac

    # ==========================================
    # RESOURCE ALLOCATION (RAM & CPU)
    # ==========================================
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}RESOURCE ALLOCATION TYPE${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e " 1) ${GREEN}Dedicated Resources${NC} (Guaranteed Hard Limit)"
    echo -e " 2) ${YELLOW}Shared / Burstable${NC} (Standard Limit)"
    echo -e " 3) ${PURPLE}System Default${NC} (Unlimited / Copy Main Host)"
    echo -n " Selection [1-3]: "
    read -r res_type

    RAM=""
    CORES=""
    USE_LIMITS=true

    if [ "$res_type" == "3" ]; then
        USE_LIMITS=false
        echo -e " ${PURPLE}>> System Default Selected: Using full Host Power.${NC}"
        sleep 1
    else
        # Ask for values if not default
        echo -n " Enter RAM Amount (e.g. 1g, 4g, 8g): "
        read -r RAM
        if [ -z "$RAM" ]; then RAM="1g"; fi
        
        echo -n " Enter CPU Cores (e.g. 1, 2, 4): "
        read -r CORES
        if [ -z "$CORES" ]; then CORES="1"; fi
    fi

    # ==========================================
    # CPU SPOOFING (Step 1 - Vendor)
    # ==========================================
    clear
    echo -e "${PURPLE}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}SELECT CPU VENDOR FAMILY${NC}"
    echo -e "${PURPLE}└──────────────────────────────────────────────────┘${NC}"
    echo -e " 1) ${RED}AuthenticAMD${NC} (Access AMD CPU List)"
    echo -e " 2) ${BLUE}GenuineIntel${NC} (Access Intel CPU List)"
    echo -e " 3) ${GREEN}Custom / Manual${NC} (Type yourself)"
    echo -e " 4) Default (Use Host CPU)"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    echo -n " Select Vendor [1-4]: "
    read -r vendor_sel

    # Defaults
    V_ID="GenuineIntel"
    C_NAME="Intel Xeon"
    C_MHZ="2500.000"
    USE_SPOOF=true

    case "$vendor_sel" in
        1) 
            # AMD SPECIFIC
            V_ID="AuthenticAMD"
            clear
            echo -e "${RED}┌──────────────────────────────────────────────────┐${NC}"
            echo -e "         ${WHITE}SELECT AMD PROCESSOR${NC}"
            echo -e "${RED}└──────────────────────────────────────────────────┘${NC}"
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
            # INTEL SPECIFIC
            V_ID="GenuineIntel"
            clear
            echo -e "${BLUE}┌──────────────────────────────────────────────────┐${NC}"
            echo -e "         ${WHITE}SELECT INTEL PROCESSOR${NC}"
            echo -e "${BLUE}└──────────────────────────────────────────────────┘${NC}"
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
            # CUSTOM
            clear
            echo -e "${GREEN}┌──────────────────────────────────────────────────┐${NC}"
            echo -e "         ${WHITE}CUSTOM CPU BUILDER${NC}"
            echo -e "${GREEN}└──────────────────────────────────────────────────┘${NC}"
            echo -n " 1. Enter Vendor ID (e.g. AuthenticAMD): "
            read -r V_ID
            echo -n " 2. Enter Model Name: "
            read -r C_NAME
            echo -n " 3. Enter Speed (MHz): "
            read -r C_MHZ
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
        sed -e "s/^vendor_id.*/vendor_id\t: $V_ID/" \
            -e "s/^model name.*/model name\t: $C_NAME/" \
            -e "s/^cpu MHz.*/cpu MHz\t\t: $C_MHZ/" \
            /proc/cpuinfo > "$CPU_FILE"
    fi

    mkdir -p "$DATA_DIR"
    
    echo -e " ${BLUE}▶${NC} Deploying container..."

    # BUILD DOCKER COMMAND STRING
    CMD="docker run -dt --name $VM_NAME --hostname $VM_ID_NAME --restart unless-stopped -v $DATA_DIR:/root:rw"

    # Add Limits if NOT "System Default"
    if [ "$USE_LIMITS" = true ]; then
        CMD="$CMD --cpus=$CORES --memory=$RAM"
    fi

    # Add Spoofing if Enabled
    if [ "$USE_SPOOF" = true ]; then
        CMD="$CMD -v $CPU_FILE:/proc/cpuinfo:ro"
    fi

    # Add Image
    CMD="$CMD $IMG /bin/bash"

    # Execute
    eval "$CMD" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        # SET PASSWORD
        echo -e " ${BLUE}∞${NC} Setting root password..."
        docker exec "$VM_NAME" /bin/bash -c "echo 'root:$VM_PASS' | chpasswd"
        
        echo -e " ${GREEN}✔ VM Installed Successfully!${NC}"
        echo -e " Redirecting to manager..."
        sleep 2
        manage_vm_menu "$VM_NAME"
    else
        echo -e " ${RED}✘ Error creating VM. (Check Docker/Storage)${NC}"
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
