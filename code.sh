#!/bin/bash

# ==================================================
#       ⚡️ NEON CYBERPUNK THEME STYLE CONSTANTS ⚡️
# ==================================================
NC='\033[0m' 
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
MAGENTA='\033[1;35m'

# ==================================================
#       🛰️ LICENSE GATEWAY PROXY
# ==================================================
LICENSE_SERVER_URL="https://githubusercontent.com"
LOCAL_LICENSE_FILE="/root/.tasin_license"

check_license() {
    clear
    echo -e "${MAGENTA}🌐𖦹──────────────────────────────────────────────────𖦹🌐${NC}"
    echo -e "   ${CYAN}⚡  METAVERSE CORE ENGINE v4.0 // TASIN PRO  ⚡${NC}"
    echo -e "   ${WHITE}      ⚡ SECURITY NODE HANDSHAKE ACTIVE ⚡${NC}"
    echo -e "${MAGENTA}🌐𖦹──────────────────────────────────────────────────𖦹🌐${NC}"
    
    if [ -f "$LOCAL_LICENSE_FILE" ]; then
        USER_KEY=$(cat "$LOCAL_LICENSE_FILE" | tr -d '[:space:]')
        echo -e " ${CYAN}⚙ [CORE LINK]${NC} Authenticating tracking index ID..."
    else
        echo -e " ${YELLOW}⚠ [UNLICENSEDED MODULE]${NC} Master license grid missing."
        echo -n " 🔗 Enter Access Token Key: "
        read -r USER_KEY
        if [ -z "$USER_KEY" ]; then echo -e "${RED}✘ Auth signature string can't be null.${NC}"; exit 1; fi
    fi

    VALID_DATA=$(curl -s --max-time 10 "$LICENSE_SERVER_URL")
    
    if [ -z "$VALID_DATA" ]; then
        echo -e " ${RED}✘ [TIMEOUT ERROR] Unable to ping GitHub Cloud Matrix node.${NC}"
        exit 1
    fi

    USER_ROW=$(echo "$VALID_DATA" | grep -w "^$USER_KEY")
    
    if [ -z "$USER_ROW" ]; then
        echo -e "${RED}✘ [ACCESS DENIED] Signature mismatch or subscription expired.${NC}"
        rm -f "$LOCAL_LICENSE_FILE"
        exit 1
    fi
    
    echo "$USER_KEY" > "$LOCAL_LICENSE_FILE"
    MAX_VMS=$(echo "$USER_ROW" | awk '{print $3}')
    if [ -z "$MAX_VMS" ]; then MAX_VMS=1; fi
    
    echo -e " ${GREEN}✔ [ONLINE]${NC} Node connected. Authorized Slots: ${CYAN}$MAX_VMS Matrix Hubs${NC}"
    sleep 1.2
}

# ==================================================
#       🛠️ DIAGNOSTIC CORE HELPERS
# ==================================================

get_status() {
    if [ "$(docker inspect -f '{{.State.Running}}' $1 2>/dev/null)" == "true" ]; then
        echo -e "${GREEN}[◈ RUNNING]${NC}"
    else
        echo -e "${RED}[■ OFFLINE]${NC}"
    fi
}

# ==================================================
#       🛸 HYPERVISOR CONTROL TERMINALS
# ==================================================

manage_vm_menu() {
    local vm_name=$1
    while true; do
        clear
        echo -e "${CYAN}🪐𖦹──────────────────────────────────────────────────𖦹🪐${NC}"
        echo -e "    🛰️ SYSTEM INTERACTION FOR LAYER: ${WHITE}$vm_name${NC}"
        echo -e "${CYAN}🪐𖦹──────────────────────────────────────────────────𖦹🪐${NC}"
        echo -e " Core Cluster Array Health: $(get_status $vm_name)"
        echo -e "${BLUE}⚡──────────────────────────────────────────────────⚡${NC}"
        echo -e "  ${CYAN}[1]${NC} 🚀 Inject TTY Terminal (Boot Console/SSH)"
        echo -e "  ${CYAN}[2]${NC} ↺  Hard Restart Node Lifecycle"
        echo -e "  ${CYAN}[3]${NC} ■  Force Kill Host Sub-routines"
        echo -e "  ${CYAN}[4]${NC} ▶  Power Up Virtual Blocks"
        echo -e "  ${CYAN}[5]${NC} ♻  Purge Stack & Reinstall Cluster OS"
        echo -e "  ${CYAN}[6]${NC} 💣 Execute Wipe Sequence (Delete Asset)"
        echo -e "  ${MAGENTA}[0]${NC} ⬅  Return to Nexus Central"
        echo -e "${BLUE}⚡──────────────────────────────────────────────────⚡${NC}"
        echo -n " Choose Matrix Vector Option: "
        read -r action

        case "$action" in
            1)
                if [ "$(docker inspect -f '{{.State.Running}}' $vm_name)" == "false" ]; then
                    echo -e " ${YELLOW}Initializing sleeping container instance...${NC}"
                    docker start $vm_name >/dev/null 2>&1
                fi
                clear
                echo -e "${GREEN}┌──────────────────────────────────────────────────┐${NC}"
                echo -e "  🚀 TERMINAL ACTIVE: Type 'exit' to bridge back.   "
                echo -e "${GREEN}└──────────────────────────────────────────────────┘${NC}"
                docker exec -it $vm_name /bin/bash
                ;;
            2)
                docker restart $vm_name
                echo -e " ${GREEN}✔ Pulse sequence reboot completed.${NC}"
                sleep 1
                ;;
            3)
                docker stop $vm_name
                echo -e " ${RED}✔ Microservice stream suspended.${NC}"
                sleep 1
                ;;
            4)
                docker start $vm_name
                echo -e " ${GREEN}✔ Block initialized successfully.${NC}"
                sleep 1
                ;;
            5)
                echo -e " ${RED}☢️ CRITICAL NOTICE: Proceeding deletes all directory databases inside $vm_name!${NC}"
                echo -n " Confirm hard wipe execution? (y/n): "
                read -r confirm
                if [ "$confirm" == "y" ]; then
                    docker rm -f $vm_name
                    rm -rf "/root/docker_data_${vm_name#tasin-vm-}"
                    rm -f "/root/cpu_${vm_name#tasin-vm-}.info"
                    echo -e " ${GREEN}✔ Block completely clean.${NC} Re-routing to provisioning panel..."
                    sleep 2
                    create_vm "${vm_name#tasin-vm-}" 
                    return
                fi
                ;;
            6)
                echo -n " Execute permanent sector destruction? (y/n): "
                read -r confirm
                if [ "$confirm" == "y" ]; then
                    docker rm -f $vm_name
                    rm -rf "/root/docker_data_${vm_name#tasin-vm-}"
                    rm -f "/root/cpu_${vm_name#tasin-vm-}.info"
                    echo -e " ${GREEN}✔ System matrix cleaned.${NC}"
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
        echo -e "${PURPLE}💠𖦹──────────────────────────────────────────────────𖦹💠${NC}"
        echo -e "         📡 NEW ARCHITECTURE ALLOCATION PROTOCOL"
        echo -e "${PURPLE}💠𖦹──────────────────────────────────────────────────𖦹💠${NC}"
        echo -n " 🔗 Set Virtual Machine Hostname (e.g., node-01): "
        read -r INPUT_NAME
        VM_ID_NAME=$(echo "$INPUT_NAME" | tr -cd 'A-Za-z0-9_-')

        echo -n " 🔑 Set Master Encryption Root Password: "
        read -r VM_PASS
        if [ -z "$VM_PASS" ]; then VM_PASS="root"; fi
    fi

    VM_NAME="tasin-vm-$VM_ID_NAME"
    DATA_DIR="/root/docker_data_$VM_ID_NAME"
    CPU_FILE="/root/cpu_$VM_ID_NAME.info"

    # ==========================================
    # OS CHIP DISTRIBUTION SELECTION
    # ==========================================
    clear
    echo -e "${CYAN}🪐𖦹──────────────────────────────────────────────────𖦹🪐${NC}"
    echo -e "         💾 CHOOSE LINUX SOURCE ISO MATRIX DISTRIBUTION"
    echo -e "${CYAN}🪐𖦹──────────────────────────────────────────────────𖦹🪐${NC}"
    echo -e " 🚀 ${YELLOW}Ubuntu Mirror Engine Labs:${NC}"
    echo -e "   [1] Ubuntu Server 22.04 LTS (Modern Core Architecture)"
    echo -e "   [2] Ubuntu Server 20.04 LTS (Stable Backport Layout)"
    echo -e "   [3] Ubuntu Server 18.04 LTS (Legacy Node Variant)"
    echo -e ""
    echo -e " ⚡ ${RED}Debian Core Cloud Layers:${NC}"
    echo -e "   [4] Debian Server 12 (Bookworm High Stability Build)"
    echo -e "   [5] Debian Server 11 (Bullseye Distribution Core)"
    echo -e "   [6] Debian Server 10 (Buster Legacy Sandbox Package)"
    echo -e ""
    echo -e " 🛸 ${BLUE}Sec-Ops Pentest & Edge Platforms:${NC}"
    echo -e "   [7] Kali Linux Rolling (Cyber Laboratories Pack)"
    echo -e "   [8] Alpine Linux Core (Ultra-Lightweight Micro Frame)"
    echo -e "${BLUE}⚡──────────────────────────────────────────────────⚡${NC}"
    echo -n " Deploy Core Choice Matrix [1-8]: "
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
    # QUANTUM RESOURCE PROVISIONING BLOCK
    # ==========================================
    clear
    if [ -c /dev/kvm ]; then
        HAS_KVM=true
        KVM_MSG="${GREEN}HARDWARE PASS-THROUGH STACK DETECTED (/dev/kvm)${NC}"
    else
        HAS_KVM=false
        KVM_MSG="${YELLOW}SOFTWARE EMULATION BACKPORT ACTIVE (No KVM Layer)${NC}"
    fi

    echo -e "${MAGENTA}🌐𖦹──────────────────────────────────────────────────𖦹🌐${NC}"
    echo -e "         🧠 QUANTUM SPACE COMPUTE MAP CONFIGURATION"
    echo -e "${MAGENTA}🌐𖦹──────────────────────────────────────────────────𖦹🌐${NC}"
    echo -e " Host Controller Hypervisor: $KVM_MSG"
    echo -e ""
    echo -e "  ${CYAN}[1] Dedicated Hardware Reservation${NC} (Strict Absolute Isolation)"
    echo -e "      * Locks exact assets directly. Bypasses standard memory tables."
    echo -e ""
    echo -e "  ${CYAN}[2] Shared Virtual Processing Layer${NC} (Burstable Cloud Server VPS)"
    echo -e "      * Dynamic shared host environment logic model."
    echo -e ""
    echo -e "  ${CYAN}[3] Multi-Cluster Host Copy Mirror${NC} (Host Frame Replication System)"
    echo -e "      * Mirrors total base server capability directly."
    echo -e "${BLUE}⚡──────────────────────────────────────────────────⚡${NC}"
echo -n " Select Computation Routing Vector [1-3]: "
read -r res_type
RAM=""
CORES=""
MODE="shared"
if [ "$res_type" == "3" ]; then
MODE="unlimited"
echo -e " ${PURPLE}>> Allocation Successful: Unlimited dynamic burst pipelines linked.${NC}"
sleep 1
else
echo -n " 💾 Map RAM Allocation Pool (e.g., 512m, 4g, 16g): "
read -r RAM
if [ -z "$RAM" ]; then RAM="1g"; fi
echo -n " 🧠 Map Logical Processor Core Limits (e.g., 1, 4, 12): "
read -r CORES
if [ -z "$CORES" ]; then CORES="1"; fi
if [ "$res_type" == "1" ]; then MODE="dedicated"; else MODE="shared"; fi
fi
# ==========================================
# CHIP HARDWARE INJECTION MATRIX SPOOFER
# ==========================================
clear
echo -e "${CYAN}🪐𖦹──────────────────────────────────────────────────𖦹🪐${NC}"
echo -e " ⚡ ARCHITECTURE VENDOR INJECTION INTERFACE"
echo -e "${CYAN}🪐𖦹──────────────────────────────────────────────────𖦹🪐${NC}"
echo -e " ${RED}[1] AuthenticAMD Silicon Core Layouts${NC}"
echo -e " ${BLUE}[2] GenuineIntel Processing Clusters${NC}"
echo -e " ${GREEN}[3] Custom Brand Engine Identity Injection${NC}"
echo -e " ${WHITE}[4] Raw Baremetal Host CPU Direct Mapping${NC}"
echo -e "${BLUE}⚡──────────────────────────────────────────────────⚡${NC}"
echo -n " Override Silicon Signature Sequence [1-4]: "
read -r vendor_sel
V_ID="GenuineIntel"
C_NAME="Intel Xeon"
C_MHZ="2500.000"
USE_SPOOF=true
case "$vendor_sel" in
1)
V_ID="AuthenticAMD"
clear
echo -e "𖦹 AMD SILICON INVENTORY ARRAY"
echo -e " [1] AMD EPYC 9654 Data Center Beast (96 Cores)"
echo -e " [2] AMD EPYC 7763 Enterprise Cloud Array (64 Cores)"
echo -e " [3] AMD Ryzen 9 7950X3D Performance Chipset"
echo -e " [4] AMD Ryzen 9 5950X Legacy Consumer Core"
echo -e " [5] AMD Ryzen Threadripper PRO 5995WX Workstation"
echo -n " Inject Array Code: "
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
echo -e "𖦹 INTEL SILICON INVENTORY ARRAY"
echo -e " [1] Intel Core i9-14900KS Frequency King (6.2 GHz)"
echo -e " [2] Intel Core i9-13900K Core Cluster"
echo -e " [3] Intel Xeon Platinum 8490H Scalable Enterprise"
echo -e " [4] Intel Xeon Gold 6130 Production Core"
echo -e " [5] Intel Core i7-12700K Processing Station"
echo -n " Inject Array Code: "
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
echo -e "⚡️ CUSTOM SPECIFICATION DEVELOPMENT SUITE"
echo -n " 1. Define Custom String Vendor String ID (e.g., AuthenticAMD): "
read -r V_ID
echo -n " 2. Define Custom String Model Label (e.g., NASA-SuperNode): "
read -r C_NAME
echo -n " 3. Define Hardware Clock Speed Rating in MHz: "
read -r C_MHZ
;;
4) USE_SPOOF=false ;;
*) USE_SPOOF=false ;;
esac
if [ "$USE_SPOOF" = true ]; then
sed -e "s/^vendor_id.*/vendor_id\t: $V_ID/" \
    -e "s/^model name.*/model name\t: $C_NAME/" \
    -e "s/^cpu MHz.*/cpu MHz\t\t: $C_MHZ/" \
    /proc/cpuinfo > "$CPU_FILE"
fi
mkdir -p "$DATA_DIR"
echo -e " ${BLUE}⚙ [COMPILING DEPLOYMENT DATA]${NC} Packing matrix modules..."
# ==========================================
# ⚙️ AUTO-REPAIR DOCKER RUN CONSTRUCTOR ENGINE
# ==========================================
DOCKER_CMD="docker run -dt --name \"$VM_NAME\" --hostname \"$VM_ID_NAME\" --restart unless-stopped -v \"$DATA_DIR\":/root:rw"
if [ "$MODE" == "dedicated" ]; then
DOCKER_CMD="$DOCKER_CMD --cpus=\"$CORES\" --memory=\"$RAM\""
# FIX: Try to append swap lock parameters but prepare for fallback bypass if host kernel has swap limits turned off
DOCKER_CMD_FINAL="$DOCKER_CMD --memory-swap=\"$RAM\""
if [ "$HAS_KVM" = true ]; then DOCKER_CMD_FINAL="$DOCKER_CMD_FINAL --device /dev/kvm"; fi
elif [ "$MODE" == "shared" ]; then
DOCKER_CMD_FINAL="$DOCKER_CMD --cpus=\"$CORES\" --memory=\"$RAM\""
else
DOCKER_CMD_FINAL="$DOCKER_CMD"
fi
if [ "$USE_SPOOF" = true ]; then DOCKER_CMD_FINAL="$DOCKER_CMD_FINAL -v \"$CPU_FILE\":/proc/cpuinfo:ro"; fi
DOCKER_CMD_FINAL="$DOCKER_CMD_FINAL \"$IMG\" /bin/bash"
# Core Execution Engine Call
eval "$DOCKER_CMD_FINAL" >/dev/null 2>&1
# CRASH WATCHER AUTOMATIC REPAIR FORGIVENESS TRIGGER
if [ $? -ne 0 ]; then
echo -e " ${YELLOW}⚠ [KERNEL LIMIT CONFLICT DETECTED]${NC} Host cgroup memory swap accounting missing. Activating fallback repair parameters..."
# FIX FALLBACK COMMAND STRIP: Drops strict system memory swaps to allow immediate initialization compatibility
DOCKER_REPAIR_CMD="docker run -dt --name \"$VM_NAME\" --hostname \"$VM_ID_NAME\" --restart unless-stopped --oom-kill-disable=false -v \"$DATA_DIR\":/root:rw"
if [ -n "$CORES" ]; then DOCKER_REPAIR_CMD="$DOCKER_REPAIR_CMD --cpus=\"$CORES\""; fi
if [ -n "$RAM" ]; then DOCKER_REPAIR_CMD="$DOCKER_REPAIR_CMD --memory=\"$RAM\""; fi
if [ "$HAS_KVM" = true ] && [ "$MODE" == "dedicated" ]; then DOCKER_REPAIR_CMD="$DOCKER_REPAIR_CMD --device /dev/kvm"; fi
if [ "$USE_SPOOF" = true ]; then DOCKER_REPAIR_CMD="$DOCKER_REPAIR_CMD -v \"$CPU_FILE\":/proc/cpuinfo:ro"; fi
DOCKER_REPAIR_CMD="$DOCKER_REPAIR_CMD \"$IMG\" /bin/bash"
eval "$DOCKER_REPAIR_CMD" >/dev/null 2>&1
fi
if [ $? -eq 0 ]; then
echo -e " ${CYAN}⚙ [KEY INJECTION]${NC} Injecting user root terminal password keys..."
sleep 1.5
docker exec "$VM_NAME" /bin/bash -c "echo 'root:$VM_PASS' | chpasswd" 2>/dev/null
echo -e " ${GREEN}✔ [PROVISIONED SUCCESSFULLY]${NC} Matrix container online."
sleep 1.5
manage_vm_menu "$VM_NAME"
else
echo -e " ${RED}✘ [SYSTEM FAULT] Creation failed. Please confirm Docker daemon service status by typing: systemctl restart docker${NC}"
sleep 4
fi
}
# ==================================================
# 🔄 MASTER MAIN GRID HUB INFRASTRUCTURE
# ==================================================
check_license
while true; do
clear
mapfile -t VMS < <(docker ps -a --format '{{.Names}}' | grep "^tasin-vm-")
echo -e "${MAGENTA}⚡𖦹──────────────────────────────────────────────────𖦹⚡${NC}"
echo -e " ${CYAN}🌌 TASIN NEXUS EDGE MASTER NETWORK CONTROLLER PANEL${NC}"
echo -e "${MAGENTA}⚡𖦹──────────────────────────────────────────────────𖦹⚡${NC}"
if [ ${#VMS[@]} -eq 0 ]; then
echo -e " ${YELLOW}[⚡ Ready Stack — Zero virtualization environments mapped]${NC}"
else
i=1
for vm in "${VMS[@]}"; do
STATE=$(get_status "$vm")
DISPLAY_NAME=${vm#tasin-vm-}
echo -e " ${CYAN}[$i]${NC} Machine Domain ID: ${WHITE}$DISPLAY_NAME${NC} ── $STATE"
((i++))
done
fi
echo -e "${BLUE}⚡──────────────────────────────────────────────────⚡${NC}"
echo -e " ${GREEN}[N] Allocate Brand New Layer VM Block${NC}"
echo -e " ${RED}[E] Disconnect Control Panel Session${NC}"
echo -e "${BLUE}⚡──────────────────────────────────────────────────⚡${NC}"
echo -n " Request Matrix Operation Task: "
read -r CHOICE
if [[ "$CHOICE" == "n" || "$CHOICE" == "N" ]]; then
if [ ${#VMS[@]} -ge "$MAX_VMS" ]; then
echo -e " ${RED}✘ Quota allocation limit reached via subscription license key ($MAX_VMS).${NC}"
sleep 2
else
create_vm
fi
elif [[ "$CHOICE" == "e" || "$CHOICE" == "E" ]]; then
clear
echo -e "${CYAN}Disconnecting virtual link session cleanly... Goodbye.${NC}"
exit 0
elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -le "${#VMS[@]}" ] && [ "$CHOICE" -gt 0 ]; then
INDEX=$((CHOICE-1))
SELECTED_VM=${VMS[$INDEX]}
manage_vm_menu "$SELECTED_VM"
else
echo -e " ${RED}Vector error selection unrecognized.${NC}"
sleep 1
fi
done
