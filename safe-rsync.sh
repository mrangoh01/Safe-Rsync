#!/bin/bash

# ==============================================================================
#                               CONFIGURATIONS
# ==============================================================================

# Src Configurations
SSH_USER="root"
SSH_KEY="/root/.ssh/id_rsa"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RUN_DATE=$(date +"%Y%m%d_%H%M")

# Log files
LOG_FILE="${BASE_DIR}/rsync_output_${RUN_DATE}.log"
PID_FILE="${BASE_DIR}/rsync_proc_${RUN_DATE}.pid"

# Files For Auditing the user
AUDIT_LOG="${BASE_DIR}/migration_audit_${RUN_DATE}.log"

LOCK_FILE="/var/run/path_migration.lock"

# Default Options
DEFAULT_IP="192.168.1.1"
DEFAULT_PORT="22"
DEFAULT_SWITCHES_1="-arvzHP --info=progress2"
DEFAULT_SWITCHES_2="-arvzHP --info=progress2 --delete-after"

# Rsync Binary paths
RSYNC_BIN="/opt/path/common/bin/rsync"
REMOTE_RSYNC_PATH="/opt/path/common/bin/rsync"

# Using for Define paths
SRC_PATHS=()
DST_PATHS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[1;36m'
CYAN='\033[1;36m'
NC='\033[0;0m'

# ==============================================================================
#                                  FUNCTIONS
# ==============================================================================

# Error handelling
fail() {
    echo -e "\n${RED}[ERROR] $1${NC}\n"
    exit 1
}

wait_for_user() {
    echo -e "${YELLOW}\n[PRESS ENTER TO CONTINUE OR CTRL+C TO ABORT]${NC}"
    read -r
}

get_network_info() {
    echo -e "${BLUE}=== STEP 0.1: Network Configuration ===${NC}"

    echo -ne "Enter Destination IP [Default: $DEFAULT_IP]: "
    read -r input_ip
    NEWSERVERIP=${input_ip:-$DEFAULT_IP}

    echo -ne "Enter SSH Port [Default: $DEFAULT_PORT]: "
    read -r input_port
    SSH_PORT=${input_port:-$DEFAULT_PORT}

    echo -e "${GREEN}Target set to -> ${SSH_USER}@${NEWSERVERIP}:${SSH_PORT}${NC}\n"
}

get_paths_configuration() {
    echo -e "${BLUE}=== STEP 0.2: Paths Configuration ===${NC}"
    echo -e "Available Default Paths Table:"
    echo -e "------------------------------------------------"
    echo -e " [1] /path/default-1/"
    echo -e " [2] /path/default-2/"
    echo -e " [3] /var/log/"
    echo -e " [C] Custom Path (Enter manually)"
    echo -e "------------------------------------------------"

    while true; do
        echo -ne "Select a path option (1-5) or 'C' for Custom [or 'D' if Done selecting]: "
        read -r choice

        case "$choice" in
            1) src="/path/default-1/" ;;
            2) src="/path/default-2/" ;;
            3) src="/var/log/" ;;
            [cC])
                echo -ne "Enter Custom SOURCE Path (e.g. /home/user/data/): "
                read -r src
                if [ -z "$src" ]; then
                    echo -e "${RED}Source path cannot be empty!${NC}"
                    continue
                fi
                ;;
            [dD])
                if [ ${#SRC_PATHS[@]} -eq 0 ]; then
                    echo -e "${RED}You must select at least one path before continuing!${NC}"
                    continue
                fi
                break
                ;;
            *)
                echo -e "${RED}Invalid option! Please try again.${NC}"
                continue
                ;;
        esac

        echo -e "Selected Source: ${YELLOW}$src${NC}"
        echo -ne "Enter DESTINATION path for this source [Press Enter to keep it identical]: "
        read -r dst

        if [ -z "$dst" ]; then
            dst="${src%\*}"
        fi

        SRC_PATHS+=("$src")
        DST_PATHS+=("$dst")
        echo -e "${GREEN}Mapped: [Source] $src  ==>  [Destination] $dst${NC}\n"
    done
}

get_rsync_switches() {
    echo -e "\n${BLUE}=== STEP 0.3: Rsync Switches Configuration ===${NC}"
    echo -e "Select Rsync Switches Profile:"
    echo -e " [1] Default Migrate Without Delete Any File (${GREEN}$DEFAULT_SWITCHES_1${NC})"
    echo -e " [2] Standard Mirror (${GREEN}$DEFAULT_SWITCHES_2${NC})"
    echo -e " [3] Custom Switches (Type your own)"

    while true; do
        echo -ne "Enter your choice (1-3): "
        read -r sw_choice

        if [ "$sw_choice" == "1" ]; then
            FINAL_SWITCHES="$DEFAULT_SWITCHES_1"
            break
        elif [ "$sw_choice" == "2" ]; then
            FINAL_SWITCHES="$DEFAULT_SWITCHES_2"
            break
        elif [ "$sw_choice" == "3" ]; then
            echo -ne "Type your custom rsync switches (e.g. -avz --exclude 'temp'): "
            read -r FINAL_SWITCHES
            if [ -z "$FINAL_SWITCHES" ]; then
                echo -e "${RED}Switches cannot be empty!${NC}"
                continue
            fi
            break
        else
            echo -e "${RED}Invalid choice!${NC}"
        fi
    done
    echo -e "${GREEN}Final Switches Set: $FINAL_SWITCHES${NC}\n"
}

write_audit_log() {
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local execution_user
    execution_user=$(whoami)

    echo "=========================================================================" >> "$AUDIT_LOG"
    echo "TIMESTAMP        : $timestamp" >> "$AUDIT_LOG"
    echo "OPERATOR USER    : $execution_user" >> "$AUDIT_LOG"
    echo "DESTINATION IP   : $NEWSERVERIP (Port: $SSH_PORT)" >> "$AUDIT_LOG"
    echo "RSYNC SWITCHES   : $FINAL_SWITCHES" >> "$AUDIT_LOG"
    echo "MAPPED PATHS     :" >> "$AUDIT_LOG"

    for i in "${!SRC_PATHS[@]}"; do
        echo "  - [SRC]: ${SRC_PATHS[$i]}  -->  [DST]: ${DST_PATHS[$i]}" >> "$AUDIT_LOG"
    done
    echo "=========================================================================" >> "$AUDIT_LOG"
}

check_ssh_connection() {
    echo -e "${BLUE}=== STEP 1: Testing SSH Connection ===${NC}"
    echo "Connecting to ${SSH_USER}@${NEWSERVERIP} on port ${SSH_PORT}..."

    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$SSH_KEY" -p "$SSH_PORT" "${SSH_USER}@${NEWSERVERIP}" "echo 'SSH_OK'" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS] SSH Connection established successfully.${NC}"
    else
        fail "Connection timed out or SSH key authentication failed!"
    fi
}

check_remote_rsync() {
    echo -e "${BLUE}=== STEP 2: Checking Active Rsync Processes on Destination ===${NC}"
    echo "Scanning remote process table for exact path conflicts..."

    local remote_ps
    remote_ps=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "${SSH_USER}@${NEWSERVERIP}" "ps -eo pid,args | grep '[r]sync'" 2>/dev/null)

    if [ -z "$remote_ps" ]; then
        echo -e "${GREEN}[OK] No active rsync process found on the remote server. Safe to proceed.${NC}"
        return 0
    fi

    local has_critical_conflict=false
    local non_conflict_processes=""

    while read -r pid cmd; do
        [ -z "$pid" ] && continue
        local line_has_conflict=false

        for dst_path in "${DST_PATHS[@]}"; do
            local clean_path="${dst_path%\*}"

            if echo "$cmd" | grep -q -F "$clean_path"; then
                echo -e "${RED}[CRITICAL CONFLICT] An active rsync is currently operating on your target path!${NC}"
                echo -e "-> ${YELLOW}Target Path:${NC} $clean_path"
                echo -e "-> ${YELLOW}Remote PID:${NC} $pid"
                echo -e "-> ${YELLOW}Full Command:${NC} $cmd\n"
                has_critical_conflict=true
                line_has_conflict=true
                break
            fi
        done

        if [ "$line_has_conflict" = false ]; then
            non_conflict_processes="${non_conflict_processes}PID: $pid -> $cmd\n"
        fi
    done <<< "$remote_ps"

    if [ "$has_critical_conflict" = true ]; then
        fail "Migration aborted due to a destination path conflict."
    fi

    if [ ! -z "$non_conflict_processes" ]; then
        echo -e "${YELLOW}[WARNING] Active rsync processes detected on the destination (No path conflicts):${NC}"
        echo -e "$non_conflict_processes"
        echo -ne "Do you want to ignore these unrelated rsync tasks and proceed? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            fail "Migration cancelled by user due to active remote rsync activities."
        fi
    fi
}

check_remote_lsof() {
    echo -e "${BLUE}=== STEP 3: Checking Open Files on Destination via lsof ===${NC}"
    echo "Scanning target directories for active file locks..."

    local has_rsync_conflict=false
    local has_minor_warnings=false
    local LOCKS_LOG="dst_processes.log"

    > "$LOCKS_LOG"

    for dst_path in "${DST_PATHS[@]}"; do
        local clean_path="${dst_path%\*}"

        local dir_exists
        dir_exists=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "${SSH_USER}@${NEWSERVERIP}" "[ -d '$clean_path' ] && echo 'YES' || echo 'NO'" 2>/dev/null)
        [ "$dir_exists" != "YES" ] && continue

        local remote_locks
        remote_locks=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "${SSH_USER}@${NEWSERVERIP}" "lsof +D '$clean_path' -t" 2>/dev/null)

        if [ ! -z "$remote_locks" ]; then
            local formatted_pids
            formatted_pids=$(echo "$remote_locks" | tr '\n' ',' | sed 's/,$//')
            local process_list
            process_list=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "${SSH_USER}@${NEWSERVERIP}" "ps -p $formatted_pids -o pid,comm,args --no-headers" 2>/dev/null)

            while read -r pid comm args; do
                [ -z "$pid" ] && continue

                if [ "$comm" == "rsync" ]; then
                    echo -e "${RED}[CRITICAL CONFLICT] Another rsync process is actively migrating data to this directory!${NC}"
                    echo -e "-> ${YELLOW}Path:${NC} $clean_path"
                    has_rsync_conflict=true
                else
                    if [ "$has_minor_warnings" = false ]; then
                        echo "=== Destination File Locks Audit Log: $(date) ===" >> "$LOCKS_LOG"
                        has_minor_warnings=true
                    fi
                    echo -e "Path: $clean_path\nPID: $pid [ $comm ]\nCommand: $args\n-----------------------------------" >> "$LOCKS_LOG"
                fi
            done <<< "$process_list"
        fi
    done
LOCKS_LOG1=$LOCKS_LOG
    if [ "$has_rsync_conflict" = true ]; then
        fail "Migration aborted. An active rsync session was detected on the destination paths."
    fi

    if [ "$has_minor_warnings" = true ]; then
        echo -e "${YELLOW}[WARNING] Some non-rsync processes are currently accessing the target paths.${NC}"
        echo -e "💡 Detailed process logs have been saved to: ${CYAN}$LOCKS_LOG${NC}"
        echo -ne "\nDo you want to ignore these locks and proceed anyway? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            fail "Migration cancelled by user after reviewing destination logs."
        fi
    fi
}

check_source_volumes() {
    echo -e "${BLUE}=== STEP 4: Checking Source Directories Size ===${NC}"
    echo -e "------------------------------------------------"
    printf "%-35s | %-10s\n" "Source Path" "Size"
    echo -e "------------------------------------------------"

    for src_path in "${SRC_PATHS[@]}"; do
        base_path="${src_path%\*}"

        if [ -d "$base_path" ]; then
            size_human=$(du -sh "$base_path" | awk '{print $1}')
            printf "${GREEN}%-35s${NC} | ${YELLOW}%-10s${NC}\n" "$base_path" "$size_human"
        else
            printf "${RED}%-35s${NC} | ${RED}%-10s${NC}\n" "$base_path" "NOT FOUND (Skipped)"
        fi
    done
    echo -e "------------------------------------------------"
}

check_destination_status() {
    echo -e "${BLUE}=== STEP 5: Validating Destination Disks & Space ===${NC}"

    for i in "${!SRC_PATHS[@]}"; do
        local src_base="${SRC_PATHS[$i]%\*}"
        local dst_base="${DST_PATHS[$i]%\*}"

        if [ ! -d "$src_base" ]; then
            continue
        fi

        echo -e "\nChecking Target Directory [ ${dst_base} ] on remote server..."

        remote_script="
            if [ ! -d '$dst_base' ]; then
                echo 'NOT_EXISTS'
                exit
            fi
            if [[ '$dst_base' == /disks/* ]]; then
                if ! mountpoint -q '$dst_base'; then
                    echo 'NOT_MOUNTED'
                    exit
                fi
            fi
            echo \$(df -P '$dst_base' | tail -1 | awk '{print \$4}') \$(df -h '$dst_base' | tail -1 | awk '{print \$4}')
        "

        remote_output=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "${SSH_USER}@${NEWSERVERIP}" "$remote_script" 2>/dev/null)

        if [ "$remote_output" == "NOT_EXISTS" ]; then
            fail "Path [ $dst_base ] does not exist on remote server!"
        elif [ "$remote_output" == "NOT_MOUNTED" ]; then
            fail "Disk [ $dst_base ] is NOT mounted properly on remote server!"
        fi

        remote_free_kb=$(echo "$remote_output" | awk '{print $1}')
        remote_free_human=$(echo "$remote_output" | awk '{print $2}')
        local_size_kb=$(du -sk "$src_base" | awk '{print $1}')
        local_human=$(du -sh "$src_base" | awk '{print $1}')

        echo -e "-> Local Data Size: ${YELLOW}$local_human${NC}"
        echo -e "-> Remote Free Space: ${GREEN}$remote_free_human${NC}"

        if [ "$local_size_kb" -gt "$remote_free_kb" ]; then
            fail "Not enough space on remote disk [ $dst_base ]!"
        else
            echo -e "${GREEN}[OK] Space validation passed for $dst_base.${NC}"
        fi
    done
}

execute_migration() {
    echo -e "${BLUE}=== STEP 6: Executing Migration in Background ===${NC}"

    write_audit_log

    for i in "${!SRC_PATHS[@]}"; do
        local src="${SRC_PATHS[$i]}"
        local dst_base="${DST_PATHS[$i]%\*}"

        if [ ! -d "${src%\*}" ]; then
            continue
        fi

        echo -e "Launching rsync for: ${YELLOW}${src}${NC} -> ${GREEN}${dst_base}${NC}"

        $RSYNC_BIN --rsync-path="$REMOTE_RSYNC_PATH" $FINAL_SWITCHES -e "ssh -C -p $SSH_PORT -i $SSH_KEY" "$src" "${SSH_USER}@${NEWSERVERIP}:${dst_base}" >> "$LOG_FILE" 2>&1 &

        RSYNC_PID=$!
        PID_ENTRY="$(date +"%Y %b %d %H:%M") : PID=${RSYNC_PID} (Path: ${src} -> ${dst_base})"
        echo "$PID_ENTRY" >> "$PID_FILE"
    done

    echo -e "\n===================================================="
    echo -e "${GREEN}All tasks have been successfully sent to Background!${NC}"
    echo -e "Audit logs saved to: ${CYAN}${AUDIT_LOG}${NC}"
    echo -e "Rsync logs saved to: ${CYAN}${LOG_FILE}${NC}"
    echo -e "PID saved to: ${CYAN}${PID_FILE}${NC}"
    echo -e "Destination Processes saved to: ${CYAN}${LOCKS_LOG1}${NC}"
    echo -e "===================================================="
}

# ==============================================================================
#                               MAIN EXECUTION
# ==============================================================================
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo -e "\n\033[0;31m[ERROR] This migration script is ALREADY running on this server!\033[0;0m\n"
    exit 1
fi

clear
echo -e "${YELLOW}====================================================${NC}"
echo -e "${YELLOW}       INTERACTIVE SAFE RSYNC V2.0.0          ${NC}"
echo -e "${YELLOW}====================================================${NC}\n"
echo -e "${YELLOW}"
cat << 'EOF'
 ____         __        ____
/ ___|  __ _ / _| ___  |  _ \ ___ _   _ _ __   ___
\___ \ / _` | |_ / _ \ | |_) / __| | | | '_ \ / __|
 ___) | (_| |  _|  __/ |  _ <\__ \ |_| | | | | (__
|____/ \__,_|_|  \___| |_| \_\___/\__, |_| |_|\___|
                                  |___/             V 2.0.0
Written By : https://github.com/mrangoh01
EOF
echo -e "${NC}\n"

get_network_info
get_paths_configuration
get_rsync_switches

check_ssh_connection
wait_for_user

check_remote_rsync
check_remote_lsof
wait_for_user

check_source_volumes
wait_for_user

check_destination_status
wait_for_user

execute_migration