#!/bin/bash

# ==================================================
#          COLOR & SMOOTH ANIMATION DEFINITIONS
# ==================================================
NC='\033[0m' 
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'

animate_text() {
    local text="$1"
    local color="$2"
    local delay=0.02
    echo -ne "$color"
    for ((i=0; i<${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo -e "$NC"
}

clear

# ==================================================
#          PREMIUM ANIMATED INTRO BANNER
# ==================================================
echo -e "${PURPLE}┌──────────────────────────────────────────────────┐${NC}"
animate_text "   ⚡ Welcome To Premium Vm maker NextGen ⚡" "$CYAN"
animate_text "   ⚡ Crafted by iTzTasin69 & HackerTeam ⚡" "$GREEN"
echo -e "${PURPLE}└──────────────────────────────────────────────────┘${NC}"
echo ""

# ==================================================
#    LICENSE VALIDATION & SYSTEM DATA SAVER
# ==================================================
# FIX: Updated URL to new MinePanel path (Cleaned 'refs/heads' for Raw compatibility)
LICENSE_SERVER_URL="https://raw.githubusercontent.com/minepaneloffcial-dotcom/project-1/refs/heads/main/license.key"
LOCAL_LICENSE_FILE="/root/.tasin_license"

# 1. Check if we have a saved key
if [ -f "$LOCAL_LICENSE_FILE" ]; then
    USER_KEY=$(cat "$LOCAL_LICENSE_FILE" | tr -d '[:space:]')
    echo -e " ${GREEN}✔${NC} Local license index detected safely."
    echo -e " ${BLUE}✦${NC} Handshaking key profile: $USER_KEY..."
    sleep 1
else
    echo -e " ${YELLOW}⚠${NC} Host environment unlicenced."
    echo -n " Enter Deployment License Key: "
    read -r USER_KEY

    if [ -z "$USER_KEY" ]; then
        echo -e " ${RED}✘ Error: License key entry cannot be null!${NC}"
        exit 1
    fi
fi

# 2. Fetch the database from GitHub
VALID_DATA=$(curl -s -L --connect-timeout 10 "$LICENSE_SERVER_URL")

# 3. Validation Logic
if [ -z "$VALID_DATA" ]; then
    echo -e " ${RED}✘ Gateway Timeout: Unable to query authentication node.${NC}"
    echo -e " ${YELLOW}Check if the URL exists: $LICENSE_SERVER_URL${NC}"
    exit 1
fi

# Check if the key exists in the fetched file
USER_ROW=$(echo "$VALID_DATA" | grep -w "^$USER_KEY" | head -n 1)

if [ -z "$USER_ROW" ]; then
    echo -e "${RED}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "  ${RED}✘ SECURITY NOTICE: KEY INVALID OR NOT FOUND${NC}"
    echo -e "  Contact support to activate key: $USER_KEY"
    echo -e "${RED}└──────────────────────────────────────────────────┘${NC}"
    rm -f "$LOCAL_LICENSE_FILE"
    exit 1
fi

# Parse Data (Format: KEY EXPIRY MAX_VMS)
EXPIRY_DATE=$(echo "$USER_ROW" | awk '{print $2}')
MAX_ALLOWED_VMS=$(echo "$USER_ROW" | awk '{print $3}')

# Set Defaults if columns missing
if [ -z "$EXPIRY_DATE" ]; then EXPIRY_DATE="2030-01-01"; fi
if [ -z "$MAX_ALLOWED_VMS" ]; then MAX_ALLOWED_VMS=1; fi

# Check Expiration
CURRENT_SECS=$(date +%s)
EXPIRY_SECS=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null)

if [ -z "$EXPIRY_SECS" ]; then
    EXPIRY_SECS=$((CURRENT_SECS + 86400))
fi

if [ "$CURRENT_SECS" -gt "$EXPIRY_SECS" ]; then
    echo -e "${RED}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "  ${RED}✘ TERM EXPIRED: This machine index ended on $EXPIRY_DATE${NC}"
    echo -e "${RED}└──────────────────────────────────────────────────┘${NC}"
    exit 1
fi

# Save valid key
echo "$USER_KEY" > "$LOCAL_LICENSE_FILE"

echo -e "${GREEN}┌──────────────────────────────────────────────────┐${NC}"
echo -e "  ${GREEN}✔ CONTAINER MANAGEMENT NODE ONLINE${NC}"
echo -e "  ${WHITE}• Expiration Lease:${NC} $EXPIRY_DATE"
echo -e "  ${WHITE}• Multi-Core Slots:${NC} $MAX_ALLOWED_VMS"
echo -e "${GREEN}└──────────────────────────────────────────────────┘${NC}"
sleep 1.2

# ==================================================
#       MULTI-VM MANAGER ENGINE INTERFACE
# ==================================================
clear
echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
echo -e "         ${WHITE}TASIN PRO MULTI-VM ENGINE MONITOR${NC}       "
echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
echo -e " Active Hypervisor Environments:"
echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
ACTIVE_VMS=$(docker ps -a --format '{{.Names}}' | grep "^tasin-vm-")

if [ -z "$ACTIVE_VMS" ]; then
    echo -e "  ${YELLOW}[⚡ Ready - No virtualization instances allocated]${NC}"
    TOTAL_VMS=0
else
    echo -e "${GREEN}$ACTIVE_VMS${NC}" | sed 's/^/  • /'
    TOTAL_VMS=$(echo "$ACTIVE_VMS" | wc -l)
fi
echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
echo -e " Cluster Workload: ${CYAN}$TOTAL_VMS${NC} / ${PURPLE}$MAX_ALLOWED_VMS${NC} Allowed Nodes"
echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
echo -e "  1) 🚀 Provision a High-Perf Virtual Instance"
echo -e "  2) 🔌 Boot & SSH-Bridge to Existing VM"
echo -e "  3) 🛑 Soft-Shutdown Running Cluster Instance"
echo -e "  4) 💣 Purge & Wipe a Virtual Instance Completely"
echo -e "  5) 🚪 Close Console Panel"
echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
echo -n " Select Action Vector [1-5]: "
read -r ENGINE_CHOICE

case "$ENGINE_CHOICE" in
    1)
        if [ "$TOTAL_VMS" -ge "$MAX_ALLOWED_VMS" ]; then
            echo -e " ${RED}✘ QUOTA EXHAUSTED: Multi-Node slots full ($MAX_ALLOWED_VMS).${NC}"
            exit 1
        fi
        
        echo ""
        echo -n " Provide Alphanumeric Label for Instance (e.g., core-db, web-01): "
        read -r UNIQUE_INPUT
        VM_ID_NAME=$(echo "$UNIQUE_INPUT" | tr -cd 'A-Za-z0-9_-')
        
        if [ -z "$VM_ID_NAME" ]; then
            echo -e " ${RED}✘ Format Fault: ID descriptor field cannot remain blank.${NC}"
            exit 1
        fi
        
        VM_NAME="tasin-vm-$VM_ID_NAME"
        DATA_DIR="/root/docker_data_$VM_ID_NAME"
        
        clear
        echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "         ${WHITE}SELECT VIRTUAL OPERATING SYSTEM SYSTEM${NC}   "
        echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
        echo -e " ${WHITE}▶ UBUNTU ARCHITECTURE:${NC}"
        echo -e "   1) ubuntu:latest      2) ubuntu:24.04"
        echo -e "   3) ubuntu:22.04      4) ubuntu:20.04"
        echo -e " ${WHITE}▶ DEBIAN ARCHITECTURE:${NC}"
        echo -e "   5) debian:latest      6) debian:13"
        echo -e "   7) debian:12          8) debian:11"
        echo -e " ${WHITE}▶ CYBER SECURITY LAB:${NC}"
        echo -e "   9) ${RED}kali-linux-rolling (Full Pentest/Flooding Pack)${NC}"
        echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
        echo -n " Select target OS platform [1-9]: "
        read -r OS_CHOICE
        
        case "$OS_CHOICE" in
            1) SELECTED_IMAGE="ubuntu:latest" ;;
            2) SELECTED_IMAGE="ubuntu:24.04" ;;
            3) SELECTED_IMAGE="ubuntu:22.04" ;;
            4) SELECTED_IMAGE="ubuntu:20.04" ;;
            5) SELECTED_IMAGE="debian:latest" ;;
            6) SELECTED_IMAGE="debian:13" ;;
            7) SELECTED_IMAGE="debian:12" ;;
            8) SELECTED_IMAGE="debian:11" ;;
            9) SELECTED_IMAGE="kalilinux/kali-rolling:latest" ;;
            *) 
               echo -e " ${YELLOW}⚠ Invalid choice. Layering standard ubuntu:22.04 LTS.${NC}"
               SELECTED_IMAGE="ubuntu:22.04" 
               ;;
        esac
        ;;
        
    2)
        if [ -z "$ACTIVE_VMS" ]; then echo "No host VM containers compiled."; exit 0; fi
        echo -n " Provide full name of Target Instance: "
        read -r VM_NAME
        clear
        echo -e " ${GREEN}▲${NC} Initializing Engine Pipeline: $VM_NAME..."
        docker start "$VM_NAME" >/dev/null 2>&1
        echo -e " ${GREEN}✔ Bridge Connected.${NC} Accessing TTY Bash Shell..."
        sleep 0.5
        docker exec -it "$VM_NAME" /bin/bash
        exit 0
        ;;
        
    3)
        if [ -z "$ACTIVE_VMS" ]; then echo "Hypervisor contains zero running layers."; exit 0; fi
        echo -n " Target Engine ID to Stop: "
        read -r VM_NAME
        docker stop "$VM_NAME" && echo -e " ${GREEN}✔ Core cycle suspended.${NC}"
        exit 0
        ;;
        
    4)
        if [ -z "$ACTIVE_VMS" ]; then echo "No persistent blocks found."; exit 0; fi
        echo -n " Target Engine ID to DESTROY: "
        read -r VM_NAME
        echo -e " ${RED}⚠ WARNING: Action is destructive. Data within the node will be dropped.${NC}"
        echo -n " Proceed with block erasure? (y/n): "
        read -r CONFIRM
        if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
            docker rm -f "$VM_NAME" >/dev/null 2>&1
            SUFFIX_DIR=$(echo "$VM_NAME" | sed 's/tasin-vm-//')
            rm -rf "/root/docker_data_$SUFFIX_DIR"
            echo -e " ${GREEN}✔ Block deleted safely. Sandbox clean.${NC}"
        fi
        exit 0
        ;;
    *)
        echo "Exiting..."
        exit 0
        ;;
esac

# ==================================================
#       INTERACTIVE HARDWARE CONFIGURATION
# ==================================================
clear
echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
echo -e "         ${WHITE}SELECT PROCESSOR EMBED VENDOR${NC}             "
echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
echo -e "  1) GenuineIntel"
echo -e "  2) AuthenticAMD"
echo -e "  3) Custom Vendor Spoof Mapping"
echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
echo -n " Apply Vector Selection [1-3]: "
read -r VENDOR_CHOICE

case "$VENDOR_CHOICE" in
    1) V_ID="GenuineIntel" ;;
    2) V_ID="AuthenticAMD" ;;
    3) 
       echo -n " Input Custom Hardware Vendor String: "
       read -r V_ID
       ;;
    *) V_ID="GenuineIntel" ;;
esac

clear
echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
echo -e "         ${WHITE}SELECT CPU PROFILES & PERFORMANCE LAYER${NC}   "
echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
echo -e "  1) AMD Ryzen 9 7950X3D @ 5.7GHz"
echo -e "  2) Intel Core i9-14900KS @ 6.2GHz"
echo -e "  3) AMD EPYC 9654 Enterprise Block"
echo -e "  4) Intel Xeon Platinum Hybrid Cluster"
echo -e "  5) Custom Manual Processor Injection"
echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
echo -n " Select Microarchitecture Profile [1-5]: "
read -r CPU_CHOICE

case "$CPU_CHOICE" in
    1) C_NAME="AMD Ryzen 9 7950X3D @ 5.7GHz" ;;
    2) C_NAME="Intel Core i9-14900KS @ 6.2GHz" ;;
    3) C_NAME="AMD EPYC 9654 @ 3.7GHz" ;;
    4) C_NAME="Intel Xeon Platinum 8490H @ 3.5GHz" ;;
    5) 
       echo -n " Type Dedicated Model Name String: "
       read -r C_NAME
       ;;
    *) C_NAME="Intel Core i9-14900KS @ 6.2GHz" ;;
esac

clear
echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
echo -e "         ${WHITE}CORE TUNING: MHZ SPEED & LOGICAL THREADS${NC} "
echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
echo -n " [!] Assign Engine Frequency (e.g., 6200.000): "
read -r C_MHZ
if [ -z "$C_MHZ" ]; then C_MHZ="5700.000"; fi

echo -n " [!] Set Maximum CPU Core Allocation (e.g., 2, 4): "
read -r CPU_CORES
if [ -z "$CPU_CORES" ]; then CPU_CORES="2"; fi

# ==================================================
#    DEDICATED ADVANCED RESOURCE CONTROLLERS (RAM/DISK)
# ==================================================
clear
echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
echo -e "         ${WHITE}SPECIFY MEMORY & METRIC STORAGE THRESHOLDS${NC}"
echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
echo -e " Define RAM parameters using size flags (e.g., 512m, 2g, 4g)."
echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
echo -n " Assign Maximum Safe Memory Boundary: "
read -r RAM_LIMIT
if [ -z "$RAM_LIMIT" ]; then RAM_LIMIT="2g"; fi

echo -n " Assign Swappable Cache Memory Limit (e.g., 0, 1g): "
read -r SWAP_LIMIT
if [ -z "$SWAP_LIMIT" ]; then SWAP_LIMIT="0"; fi

echo -n " Constrain Disk Write Throughput Limit (MB/s, e.g., 50m): "
read -r IO_WRITE
if [ -z "$IO_WRITE" ]; then IO_WRITE="100m"; fi

# ==================================================
#          CORE CONFIGURATION & CONTAINER BUILD
# ==================================================
if [ ! -d "$DATA_DIR" ]; then mkdir -p "$DATA_DIR"; fi

# Fixed multi-line split syntax for sed operation
sed -e "s/^vendor_id.*/vendor_id\t: $V_ID/" \
    -e "s/^model name.*/model name\t: $C_NAME/" \
    -e "s/^cpu MHz.*/cpu MHz\t\t: $C_MHZ/" \
    /proc/cpuinfo > /root/cpu.vm

clear
echo -e "${GREEN}┌──────────────────────────────────────────────────┐${NC}"
echo -e "         ${WHITE}PROVISIONING ARCHITECTURE BY TASIN${NC}        "
echo -e "${GREEN}└──────────────────────────────────────────────────┘${NC}"
echo -e "  🚀 Deploying Node ID : ${CYAN}$VM_NAME${NC}"
echo -e "  📦 Selected OS Image : ${YELLOW}$SELECTED_IMAGE${NC}"
echo -e "  🧠 CPU Core Allocation: ${WHITE}$CPU_CORES Cores @ $C_MHZ MHz${NC}"
echo -e "  📟 Memory Allocation : ${WHITE}$RAM_LIMIT (Swap: $SWAP_LIMIT)${NC}"
echo -e "  💾 Storage Path IO   : ${WHITE}$DATA_DIR ($IO_WRITE Read/Write Cap)${NC}"
echo -e "${GREEN}────────────────────────────────────────────────────${NC}"
echo -e "  System deployment starting immediately..."
sleep 2

# Docker container initialization execution 
if [ -c /dev/kvm ]; then
    docker run -it \
      --name "$VM_NAME" \
      --hostname "$VM_ID_NAME" \
      --cpus="$CPU_CORES" \
      --memory="$RAM_LIMIT" \
      --memory-swap="$SWAP_LIMIT" \
      --device-write-bps /dev/sda:"$IO_WRITE" \
      --device /dev/kvm \
      -v /root/cpu.vm:/proc/cpuinfo:ro \
      -v "$DATA_DIR":/root:rw \
      "$SELECTED_IMAGE" /bin/bash
else
    docker run -it \
      --name "$VM_NAME" \
      --hostname "$VM_ID_NAME" \
      --cpus="$CPU_CORES" \
      --memory="$RAM_LIMIT" \
      --memory-swap="$SWAP_LIMIT" \
      --device-write-bps /dev/sda:"$IO_WRITE" \
      -v /root/cpu.vm:/proc/cpuinfo:ro \
      -v "$DATA_DIR":/root:rw \
      "$SELECTED_IMAGE" /bin/bash
fi
