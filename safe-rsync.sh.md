```bash
#!/bin/bash

  

# ==============================================================================

#                               CONFIGURATIONS

# ==============================================================================

NEWSERVERIP="192.168.1.1"

SSH_USER="root"

SSH_PORT="22"

SSH_KEY="/root/.ssh/id_rsa"

  

#Default paths in SRC & DST

#Make sure you have paths in both SRC & DST servers

PATHS=(

    "/path/1-default/*"

    "/path/2-default/*"

    "/path/3-default/*"

    "/path/4-default/*"

)

  

#Default rsync & output files paths

RSYNC_BIN="/opt/path/common/bin/rsync"

REMOTE_RSYNC_PATH="/opt/path/common/bin/rsync"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LOG_FILE="${BASE_DIR}/rsync_output.log"

PID_FILE="${BASE_DIR}/rsync_proc.pid"

  

#Rsync switches

DEFAULT_SWITCHES="-arvzHP --info=progress2"

  

#just a few designing for a better look

RED='\033[0;31m'

GREEN='\033[0;32m'

YELLOW='\033[0;33m'

BLUE='\033[1;36m'

CYAN='\033[0;36m'

NC='\033[0;0m' # No Color

  

# ==============================================================================

#                                   FUNCTIONS

# ==============================================================================

  

#Force stop

fail() {

    echo -e "\n${RED}[ERROR] $1${NC}\n"

    exit 1

}

  

#User validation (press ENTER)

wait_for_user() {

    echo -e "${YELLOW}\n[PRESS ENTER TO CONTINUE OR CTRL+C TO ABORT]${NC}"

    read -r

}

  

#Do you think it needs any comment??

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

#Check for any rsync proccess running in DST server(just by name filtering)

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

  

        for path_pattern in "${PATHS[@]}"; do

            local clean_path="${path_pattern%\*}"

  

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

        fail "Migration aborted due to a destination path conflict. Please wait for the remote rsync to finish or terminate it."

    fi

  

    if [ ! -z "$non_conflict_processes" ]; then

        echo -e "${YELLOW}[WARNING] Active rsync processes detected on the destination (No path conflicts):${NC}"

        echo -e "$non_conflict_processes"

  

        echo -ne "Do you want to ignore these unrelated rsync tasks and proceed? [y/N]: "

        read -r response

        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then

            fail "Migration cancelled by user due to active remote rsync activities."

        fi

        echo -e "${GREEN}Warning ignored. Moving to the next step...${NC}"

    fi

}

#Check for any rsync proccess running in DST server(with lsof in OS layer)

check_remote_lsof() {

    echo -e "${BLUE}=== STEP 3: Checking Open Files on Destination via lsof ===${NC}"

    echo "Scanning target directories for active file locks..."

  

    local has_rsync_conflict=false

    local has_minor_warnings=false

    local LOCKS_LOG="dst_processes.log"

  

    > "$LOCKS_LOG"

  

    for path_pattern in "${PATHS[@]}"; do

        local clean_path="${path_pattern%\*}"

  

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

                    echo -e "-> ${YELLOW}Remote PID:${NC} $pid"

                    echo -e "-> ${YELLOW}Command:${NC} $args\n"

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

  

    if [ "$has_rsync_conflict" = true ]; then

        fail "Migration aborted. An active rsync session was detected on the destination paths. You CANNOT run multiple instances."

    fi

  

    if [ "$has_minor_warnings" = true ]; then

        echo -e "${YELLOW}[WARNING] Some non-rsync processes are currently accessing the target paths.${NC}"

        echo -e "💡 Detailed process logs have been saved to: ${CYAN}$LOCKS_LOG${NC}"

        echo -e "👉 Check this file in another terminal using: ${GREEN}cat $LOCKS_LOG${NC}"

  

        echo -ne "\nDo you want to ignore these locks and proceed anyway? [y/N]: "

        read -r response

        if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then

            fail "Migration cancelled by user after reviewing destination logs."

        fi

        echo -e "${GREEN}Warning ignored. Moving to the next step...${NC}"

    else

        echo -e "${GREEN}[OK] No conflicting file locks detected on target paths.${NC}"

    fi

}

  

#Check the size of the SRC directories

check_source_volumes() {

    echo -e "${BLUE}=== STEP 5: Checking Source Directories Size ===${NC}"

    echo -e "------------------------------------------------"

    printf "%-35s | %-10s\n" "Source Path" "Size"

    echo -e "------------------------------------------------"

  

    for path_pattern in "${PATHS[@]}"; do

        #remove "*" for run "du -sh"

        base_path="${path_pattern%\*}"

  

        if [ -d "$base_path" ]; then

            size_human=$(du -sh "$base_path" | awk '{print $1}')

            printf "${GREEN}%-35s${NC} | ${YELLOW}%-10s${NC}\n" "$base_path" "$size_human"

        else

            printf "${RED}%-35s${NC} | ${RED}%-10s${NC}\n" "$base_path" "NOT FOUND (Skipped)"

        fi

    done

    echo -e "------------------------------------------------"

}

  

#Check the existence, mount status, and volume of disks at the DST

check_destination_status() {

    echo -e "${BLUE}=== STEP 6: Validating Destination Disks & Space ===${NC}"

  

    for path_pattern in "${PATHS[@]}"; do

        base_path="${path_pattern%\*}"

  

        #Dont Check the existence in SRC

        if [ ! -d "$base_path" ]; then

            continue

        fi

  

        echo -e "\nChecking ${base_path} on remote server..."

  

        #Remote commands to check directory existence, mount point (for /disks/ paths) and free volume

        remote_script="

            if [ ! -d '$base_path' ]; then

                echo '$base_path NOT_EXISTS'

                exit

            fi

            if [[ '$base_path' == /disks/* ]]; then

                if ! mountpoint -q '$base_path'; then

                    echo '$base_path NOT_MOUNTED'

                    exit

                fi

            fi

            df -P '$base_path' | tail -1 | awk '{print \$4}' #Size(KB)

        "

  

        remote_output=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "${SSH_USER}@${NEWSERVERIP}" "$remote_script" 2>/dev/null)

  

        if [ "$remote_output" == "NOT_EXISTS" ]; then

            fail "Path [ $base_path ] does not exist on remote server!"

        elif [ "$remote_output" == "NOT_MOUNTED" ]; then

            fail "Disk [ $base_path ] is NOT mounted properly on remote server!"

        fi

  

        #Some mathematics (compare volumes)

        local_size_kb=$(du -sk "$base_path" | awk '{print $1}')

        remote_free_kb=$remote_output

  

        local_human=$(du -sh "$base_path" | awk '{print $1}')

        remote_free_human=$(ssh -i "$SSH_KEY" -p "$SSH_PORT" "${SSH_USER}@${NEWSERVERIP}" "df -h '$base_path' | tail -1 | awk '{print \$4}'" 2>/dev/null)

  

        echo -e "-> Local Data Size: ${YELLOW}$local_human${NC}"

        echo -e "-> Remote Free Space: ${GREEN}$remote_free_human${NC}"

  

        if [ "$local_size_kb" -gt "$remote_free_kb" ]; then

            fail "Not enough space on remote disk [ $base_path ]! Free up space and try again."

        else

            echo -e "${GREEN}[OK] Space validation passed for $base_path.${NC}"

        fi

    done

}

  

#Interactive review rsync switches

configure_rsync_switches() {

    echo -e "${BLUE}=== STEP 7: Reviewing Rsync Switches ===${NC}"

    echo -e "Base Switches: ${GREEN}${DEFAULT_SWITCHES}${NC} (Archive, Verbose, Compress, Human-readable, Resume)"

  

    echo -ne "\nDo you want to include ${YELLOW}--delete-after${NC}? (This deletes files in destination that don't exist in source after transfer) [Y/n]: "

    read -r response

  

    if [[ -z "$response" || "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then

        FINAL_SWITCHES="${DEFAULT_SWITCHES} --delete-after"

        echo -e "${GREEN}Added --delete-after to final command.${NC}"

    else

        FINAL_SWITCHES="${DEFAULT_SWITCHES}"

        echo -e "${YELLOW}Skipped --delete-after.${NC}"

    fi

}

  

#Executation & logging(log file + PID-log file )

execute_migration() {

    echo -e "${BLUE}=== STEP 8: Executing Migration in Background ===${NC}"

    echo -e "Log file location: ${YELLOW}${LOG_FILE}${NC}"

    echo -e "PID log file location: ${YELLOW}${PID_FILE}${NC}"

  

    echo -e "\n${GREEN}Starting synchronization for active paths...${NC}"

  

    for path_pattern in "${PATHS[@]}"; do

        base_path="${path_pattern%\*}"

  

        #Ignoring SRC paths existence

        if [ ! -d "$base_path" ]; then

            continue

        fi

  

        echo -e "\n------------------------------------------------"

        echo -e "Launching rsync for: ${YELLOW}${path_pattern}${NC}"

  

        #Rsync executation command

        $RSYNC_BIN --rsync-path="$REMOTE_RSYNC_PATH" $FINAL_SWITCHES \

            -e "ssh -C -p $SSH_PORT -i $SSH_KEY" \

            "$path_pattern" "${SSH_USER}@${NEWSERVERIP}:${base_path}" >> "$LOG_FILE" 2>&1 &

  

        #Variable for PID logging

        RSYNC_PID=$!

  

        #Logging format

        CURRENT_TIME=$(date +"%Y %b %d %H:%M")

        PID_ENTRY="${CURRENT_TIME} : PID=${RSYNC_PID} (Path: ${base_path})"

  

        #Create & appending PID-log file

        echo "$PID_ENTRY" >> "$PID_FILE"

  

        #Print in Terminal

        echo -e "-> ${GREEN}Rsync started in Background!${NC}"

        echo -e "-> Logged Entry: ${BLUE}${PID_ENTRY}${NC}"

    done

  

    echo -e "\n===================================================="

    echo -e "${GREEN}All tasks have been successfully sent to Background!${NC}"

    echo -e "You can close this terminal safely."

    echo -e "To monitor progress manually, run: ${YELLOW}tail -f ${LOG_FILE}${NC}"

    echo -e "===================================================="

}

  

# ==============================================================================

#                               MAIN EXECUTION

# ==============================================================================

clear

echo -e "${YELLOW}====================================================${NC}"

echo -e "${YELLOW}       HIGH-VOLUME DATA Transfer SCRIPT             ${NC}"

echo -e "${YELLOW}====================================================${NC}\n"

echo -e "${YELLOW}"

cat << 'EOF'

 ____         __        ____

/ ___|  __ _ / _| ___  |  _ \ ___ _   _ _ __   ___

\___ \ / _` | |_ / _ \ | |_) / __| | | | '_ \ / __|

 ___) | (_| |  _|  __/ |  _ <\__ \ |_| | | | | (__

|____/ \__,_|_|  \___| |_| \_\___/\__, |_| |_|\___|

                                  |___/

Written By : https://github.com/mrangoh01

EOF

echo -e "${NC}\n"

  
  

check_ssh_connection

wait_for_user

  

check_remote_rsync

check_remote_lsof

#wait_for_user

  

check_source_volumes

wait_for_user

  

check_destination_status

wait_for_user

  

configure_rsync_switches

wait_for_user

  

execute_migration
```