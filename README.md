# safe-rsync (v2.0.0)

```text
 ____         __        ____
/ ___|  __ _ / _| ___  |  _ \ ___ _   _ _ __   ___
\___ \ / _` | |_ / _ \ | |_) / __| | | | '_ \ / __|
 ___) | (_| |  _|  __/ |  _ <\__ \ |_| | | | | (__
|____/ \__,_|_|  \___| |_| \_\___/\__, |_| |_|\___|
                                  |___/             V 2.0.0
```

`safe-rsync` v2.0.0 is a major upgrade to the original enterprise-grade data migration script. It transitions from static file configurations to a fully **interactive, dynamic CLI workflow** while introducing local script lock protection (`flock`) and full operator auditing.

## 🆕 What's New in Version 2.0.0?

Compared to v1.0.0, the second version introduces key enhancements:

- **Interactive Network & Path Configuration:** No more hardcoding target IPs or paths in the script. Prompts guide you through setting destination IP, SSH port, and path mappings interactively.
    
- **Flexible Source-to-Destination Path Mapping:** Supports mapping custom source paths to completely different destination directory structures dynamically.
    
- **Local Process File Locking (`flock`):** Utilizes `/var/run/path_migration.lock` to strictly prevent duplicate parallel script executions on the source node.
    
- **Compliance & Operator Audit Logging:** Automatically logs migration metadata (operator username, timestamp, switches, network info, path mappings) into `migration_audit_<TIMESTAMP>.log`.
    
- **Dynamic Timestamped Output Files:** Log files and process PID records now use run-specific timestamps (`YYYYMMDD_HHMM`) to prevent log overwrites across migration sessions.
    
- **Selectable Rsync Profile Switches:** Offers pre-configured profiles (standard migration, mirror transfer with deletion, or custom switches) on the fly.
    

## Key Features

- **SSH Reachability Pre-flight Verification:** Validates network routing and SSH key authentication before executing data transfers.
    
- **Destination Conflict Detection (`ps` & `lsof`):** Scans the target host for active `rsync` tasks or file descriptor locks on destination folders.
    
- **Storage Capacity Check:** Calculates local source usage (`du`) against destination volume availability (`df`).
    
- **Local Lock Engine:** Prevents duplicate migration processes via kernel-level file locks (`flock`).
    

## Quick Start
```bash
git clone https://github.com/mrangoh01/Safe-Rsync.git
cd Safe-Rsync
chmod +x safe-rsync.sh

# Launch interactive setup
./safe-rsync.sh
```

## Usage Workflow Example

When launched, `safe-rsync` v2.0.0 guides you through three interactive setup steps:

1. **Network Setup:** Input destination IP and SSH port (or press Enter for default values).
    
2. **Path Mapping:** Select standard paths or define custom source and target paths.
    
3. **Switch Selection:** Pick between Standard Sync, Delete/Mirror Sync, or custom flags.