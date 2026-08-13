```text
 ____         __        ____
/ ___|  __ _ / _| ___  |  _ \ ___ _   _ _ __   ___
\___ \ / _` | |_ / _ \ | |_) / __| | | | '_ \ / __|
 ___) | (_| |  _|  __/ |  _ <\__ \ |_| | | | | (__
|____/ \__,_|_|  \___| |_| \_\___/\__, |_| |_|\___|
                                  |___/
```

An automated, safety-first Bash framework designed for high-volume data migrations across Linux servers. `safe-rsync` validates SSH connectivity, inspects destination process tables and open file handles, verifies storage capacity, and safely background-executes file transfers with real-time log tracking.

## Key Features

- **SSH Connection Pre-flight Check:** Validates network reachability and SSH key authentication before initiating any transfer tasks.
    
- **Dual-Layer Destination Conflict Detection:**
    
    - **Process Audit (`ps`):** Scans the destination process tree to detect running `rsync` instances targeting identical path patterns.
        
    - **File Lock Audit (`lsof`):** Inspects target mount points on the destination host for active file descriptor locks.
        
- **Bi-Directional Capacity Validation:** Computes local source folder sizes (`du`) and cross-checks against available remote filesystem volume space (`df`).
    
- **Background Execution & Live Logging:** Spawns data migration tasks in the background while streaming structured timestamps, PIDs, and progress logs to dedicated files.
    
- **Script Re-execution Prevention:** Employs lock mechanisms to prevent duplicate parallel runs that could saturate network interfaces or disrupt active migrations.
    

## Warnings & Configurations

### 1. Passwordless SSH Setup

`safe-rsync` requires passwordless SSH key authentication. Generate an SSH key (without a passphrase for fully automated operations) and copy it to the destination server:
```bash
ssh-keygen -t rsa -b 4096 -C "migration-key"
ssh-copy-id -i ~/.ssh/id_rsa.pub root@<DESTINATION_IP>
```
**Warning:** Ensure the SSH key specified in the configuration has strict read/write permissions on both local and remote nodes.

### 2. Destination Server Variables

Configure the destination connection metadata in the script header:
```bash
NEWSERVERIP="192.168.1.1"   # Target Server IP Address
SSH_USER="root"             # SSH Username on Destination
SSH_PORT="22"               # SSH Service Port
SSH_KEY="/root/.ssh/id_rsa" # Absolute Path to Private Key
```

### 3. Transfer Path Definitions

Define source path wildcards in the `PATHS` array:
```bash
PATHS=(
    "/path/1-default/*"
    "/path/2-default/*"
    "/path/3-default/*"
)
```
**CRITICAL REQUIREMENT:** Every path specified in the `PATHS` array **MUST exist on the destination server prior to execution**. The script explicitly verifies remote directory existence and mount point integrity (`/disks/*`). If a directory is missing or unmounted, execution will terminate immediately.

### 4. Custom Binary Paths

Specify binary paths if running non-standard or custom-compiled `rsync` installations:
```bash
RSYNC_BIN="/opt/path/common/bin/rsync"        # Local Rsync Binary
REMOTE_RSYNC_PATH="/opt/path/common/bin/rsync" # Destination Rsync Binary
```

### 5. Bandwidth Throttling (`--bwlimit`)

To prevent network congestion during peak operational hours, include the `--bwlimit` switch in your `DEFAULT_SWITCHES` configuration:
```bash
DEFAULT_SWITCHES="-arvzHP --info=progress2 --bwlimit=10240"
```
**Description:** Limits maximum socket transfer speed. Value is specified in **KBytes per second** (e.g., `--bwlimit=10240` caps bandwidth at **10 MB/s**).

## Quick Start
```bash
git clone https://github.com/mrangoh01/safe-rsync.git
cd safe-rsync
chmod +x safe-rsync.sh
./safe-rsync.sh
```

## Monitoring & Management

Once launched, jobs run in the background. Monitor active progress using:
```bash
# Stream live migration log
tail -f rsync_output.log

# Inspect recorded execution PIDs
cat rsync_proc.pid
```