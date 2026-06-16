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
#       LOG FILE SETUP
# ==================================================
LOG_FILE="/root/vm_manager.log"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
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
                    docker rm -f $vm_name >/dev/null 2>&1
                    rm -rf "/root/docker_data_${vm_name#tasin-vm-}"
                    rm -f "/root/cpu_${vm_name#tasin-vm-}.info"
                    rm -f "/root/dmi_product_${vm_name#tasin-vm-}.info"
                    rm -f "/root/dmi_vendor_${vm_name#tasin-vm-}.info"
                    log_msg "VM Wiped: $vm_name"
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
                    docker rm -f $vm_name >/dev/null 2>&1
                    rm -rf "/root/docker_data_${vm_name#tasin-vm-}"
                    rm -f "/root/cpu_${vm_name#tasin-vm-}.info"
                    rm -f "/root/dmi_product_${vm_name#tasin-vm-}.info"
                    rm -f "/root/dmi_vendor_${vm_name#tasin-vm-}.info"
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

create_vm() {
    if [ -n "$1" ]; then
        VM_ID_NAME=$1
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "         ${WHITE}REINSTALLING: ${VM_ID_NAME}${NC}"
        echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
        echo -n " Set New Root Password: "
        read -r VM_PASS
        if [ -z "$VM_PASS" ]; then VM_PASS="root"; fi
    else
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "         ${WHITE}CREATE NEW INSTANCE${NC}"
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
    # IP SPOOFER
    # ==========================================
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}SET IP ADDRESS (DEEP SPOOF)${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e " This will fake the IP shown in 'ip addr', 'curl ifconfig.me', and 'curl ipinfo.io'."
    echo -e " Leave blank if you want it to show the default Host IP."
    echo -n " Enter IP to display (e.g. 103.186.52.163): "
    read -r SPOOF_IP

    # ==========================================
    # RESOURCE ALLOCATION (RAM & CPU)
    # ==========================================
    clear
    if [ -c /dev/kvm ]; then
        HAS_KVM=true
        KVM_MSG="${GREEN}Detected (/dev/kvm)${NC}"
    else
        HAS_KVM=false
        KVM_MSG="${RED}Not Detected (Software Mode)${NC}"
    fi

    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "         ${WHITE}RESOURCE ALLOCATION TYPE${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -e " Hypervisor Status: $KVM_MSG"
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
        if [ "$HAS_KVM" = true ]; then
             CMD="$CMD --device /dev/kvm"
        fi
    elif [ "$MODE" == "shared" ]; then
        CMD="$CMD --cpus=$CORES --memory=$RAM"
    fi

    # ADD CPU SPOOFING
    if [ "$USE_SPOOF" = true ]; then
        CMD="$CMD -v $CPU_FILE:/proc/cpuinfo:ro"
    fi

    # ADD DMI MODEL SPOOFING (Mounted to /etc/ to avoid kernel permission errors)
    if [ -n "$MODEL_NAME" ]; then
        CMD="$CMD -v $DMI_PRODUCT_FILE:/etc/custom_product_name:ro"
        CMD="$CMD -v $DMI_VENDOR_FILE:/etc/custom_sys_vendor:ro"
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

        # 2. FIX UPTIME: Override uptime command to show VM-only uptime (starts from 0)
        cat << 'UPTIME_WRAP' > /tmp/uptime_wrap
#!/bin/bash
# Get uptime of PID 1 (Container start time, not Host time)
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

        # 3. Deep IP Spoofing
        if [ -n "$SPOOF_IP" ]; then
            log_msg "Applying Deep IP Spoof: $SPOOF_IP to $VM_NAME"
            docker exec "$VM_NAME" $VM_SHELL -c "ip addr add $SPOOF_IP/32 dev eth0 2>/dev/null || true"
            echo "ip addr add $SPOOF_IP/32 dev eth0 2>/dev/null" | docker exec -i "$VM_NAME" $VM_SHELL -c "cat >> /root/.bashrc"

            cat << CURL_SPOOF > /tmp/curl_wrapper
#!/bin/bash
REAL_CURL=/usr/bin/curl
ARGS="\$@"

IP_SITES=("ifconfig.me" "ipinfo.io" "icanhazip.com" "api.ipify.org" "checkip.amazonaws.com" "ip.sb" "myip.ipip.net")

for site in "\${IP_SITES[@]}"; do
    if [[ "\$ARGS" == *"\$site"* ]]; then
        if [[ "\$ARGS" == *"ipinfo.io"* ]] && [[ "\$ARGS" != *"/ip"* ]]; then
            echo "{\"ip\": \"$SPOOF_IP\", \"city\": \"Council Bluffs\", \"region\": \"Iowa\", \"country\": \"US\", \"loc\": \"41.2619,-95.8608\", \"org\": \"AS396982 Google LLC\", \"postal\": \"51503\", \"timezone\": \"America/Chicago\"}"
        else
            echo "$SPOOF_IP"
        fi
        exit 0
    fi
done

\$REAL_CURL "\$ARGS"
CURL_SPOOF

            docker cp /tmp/curl_wrapper "$VM_NAME":/usr/local/bin/curl
            docker exec "$VM_NAME" $VM_SHELL -c "chmod +x /usr/local/bin/curl"
            rm /tmp/curl_wrapper

            cat << WGET_SPOOF > /tmp/wget_wrapper
#!/bin/bash
REAL_WGET=/usr/bin/wget
ARGS="\$@"

IP_SITES=("ifconfig.me" "ipinfo.io" "icanhazip.com" "api.ipify.org" "checkip.amazonaws.com" "ip.sb" "myip.ipip.net")

for site in "\${IP_SITES[@]}"; do
    if [[ "\$ARGS" == *"\$site"* ]]; then
        echo "$SPOOF_IP"
        exit 0
    fi
done

\$REAL_WGET "\$ARGS"
WGET_SPOOF

            docker cp /tmp/wget_wrapper "$VM_NAME":/usr/local/bin/wget
            docker exec "$VM_NAME" $VM_SHELL -c "chmod +x /usr/local/bin/wget"
            rm /tmp/wget_wrapper
        fi

        # 4. Install Packages (Neofetch remains 100% default, no config edits)
        if [ "$PTERO_MODE" = true ]; then
            echo -e " ${BLUE}∞${NC} Installing Docker CE for Pterodactyl (Please wait, this takes a minute)..."
            
            # Pre-configure daemon.json
            docker exec "$VM_NAME" bash -c "mkdir -p /etc/docker && echo '{\"storage-driver\": \"vfs\", \"iptables\": false}' > /etc/docker/daemon.json"
            
            # Install Dependencies
            docker exec "$VM_NAME" bash -c "apt-get update -qq && apt-get install -y -qq ca-certificates curl gnupg lsb-release neofetch iproute2 procps >/dev/null 2>&1"
            
            # Redirect Neofetch Host detection to our custom mounted file
            if [ -n "$MODEL_NAME" ]; then
                docker exec "$VM_NAME" bash -c "sed -i 's|/sys/class/dmi/id/product_name|/etc/custom_product_name|g; s|/sys/devices/virtual/dmi/id/product_name|/etc/custom_product_name|g' /usr/bin/neofetch"
                docker exec "$VM_NAME" bash -c "sed -i 's|/sys/class/dmi/id/sys_vendor|/etc/custom_sys_vendor|g; s|/sys/devices/virtual/dmi/id/sys_vendor|/etc/custom_sys_vendor|g' /usr/bin/neofetch"
            fi
            
            # Add Docker Official Repo
            docker exec "$VM_NAME" bash -c "mkdir -p /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg >/dev/null 2>&1"
            docker exec "$VM_NAME" bash -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null"
            
            # Install Docker CE
            docker exec "$VM_NAME" bash -c "apt-get update -qq && apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1"
            
            # Start Docker via systemctl
            docker exec "$VM_NAME" bash -c "systemctl enable docker >/dev/null 2>&1 && systemctl start docker >/dev/null 2>&1"
            
            # FALLBACK
            docker exec "$VM_NAME" bash -c "sleep 2 && if ! docker ps >/dev/null 2>&1; then dockerd --storage-driver=vfs --iptables=false > /var/log/dockerd.log 2>&1 & fi"
            
            # Auto-start script
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
            docker exec "$VM_NAME" $VM_SHELL -c "nohup bash -c 'apt-get update -qq && apt-get install -y -qq neofetch curl wget iproute2 procps >/dev/null 2>&1 && apk add neofetch curl wget iproute2 >/dev/null 2>&1' >/dev/null 2>&1 &"
            
            # Redirect Neofetch Host detection to our custom mounted file
            if [ -n "$MODEL_NAME" ]; then
                # Wait for neofetch to install before patching
                sleep 10
                docker exec "$VM_NAME" $VM_SHELL -c "if [ -f /usr/bin/neofetch ]; then sed -i 's|/sys/class/dmi/id/product_name|/etc/custom_product_name|g; s|/sys/devices/virtual/dmi/id/product_name|/etc/custom_product_name|g' /usr/bin/neofetch; fi"
                docker exec "$VM_NAME" $VM_SHELL -c "if [ -f /usr/bin/neofetch ]; then sed -i 's|/sys/class/dmi/id/sys_vendor|/etc/custom_sys_vendor|g; s|/sys/devices/virtual/dmi/id/sys_vendor|/etc/custom_sys_vendor|g' /usr/bin/neofetch; fi"
            fi
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
        sleep 5
    fi
}

# ==================================================
#       MAIN LOOP
# ==================================================

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
    echo -e "  ${YELLOW}[F]${NC} Fix Docker (OverlayFS Error)"
    echo -e "  ${RED}[E]${NC} Exit Panel"
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
    echo -n " Enter Number to Manage or [N]: "
    read -r CHOICE
    
    if [[ "$CHOICE" == "n" || "$CHOICE" == "N" ]]; then
         create_vm
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
