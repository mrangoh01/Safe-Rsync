This version introduces interactive modularization, local file locks, and comprehensive auditing.

---

## 1. Version 1.0 vs Version 2.0 Comparison Matrix

| Feature | Version 1.0.0 | Version 2.0.0 |
| :--- | :--- | :--- |
| **Configuration Style** | Hardcoded inside script file | Interactive CLI Prompts (`get_network_info`, etc.) |
| **Path Mapping** | Fixed identical source/destination paths | Dynamic custom `SRC` to `DST` mapping arrays |
| **Concurrency Control** | Remote checks only (`ps`/`lsof`) | **Dual Control:** Kernel `flock` (Local) + `ps`/`lsof` (Remote) |
| **Log Management** | Static log filenames (overwritten each run) | Timestamped files (`*_YYYYMMDD_HHMM.log`) |
| **Auditing** | Basic terminal output logging | Structured operator audit files (`migration_audit_*.log`) |
| **Rsync Profile Options** | Fixed default switches | Menu-driven profile choice (Safe, Mirror, Custom) |

---

## 2. Updated Execution Flow Diagram

```text
                     +----------------------------------+
                     |  flock Check (/var/run/*.lock)   |
                     +----------------------------------+
                                      |
                                      v
                     +----------------------------------+
                     |  get_network_info() (IP/Port)    |
                     +----------------------------------+
                                      |
                                      v
                     +----------------------------------+
                     | get_paths_configuration() (SRC->DST)|
                     +----------------------------------+
                                      |
                                      v
                     +----------------------------------+
                     |    get_rsync_switches() Menu     |
                     +----------------------------------+
                                      |
                                      v
                     +----------------------------------+
                     | check_ssh_connection() & Checks  |
                     +----------------------------------+
                                      |
                                      v
                     +----------------------------------+
                     | write_audit_log() & Background Run|
                     +----------------------------------+
````

## 3. Detailed Function Specifications (v2.0.0 Additions)

### `get_network_info()`

- **Purpose:** Collects destination server parameters.
    
- **Behavior:** Prompts for `NEWSERVERIP` and `SSH_PORT`. Defaults to pre-configured fallback values if input is empty.
    

### `get_paths_configuration()`

- **Purpose:** Dynamic path array builder.
    
- **Behavior:** Displays a list of default system paths or allows manual custom input. Maps each `SRC_PATH` to its designated `DST_PATH`.
    

### `get_rsync_switches()`

- **Purpose:** Interactive transfer mode selector.
    
- **Behavior:** Provides three execution modes:
    
    1. _Safe Migration_ (`-arvzHP --info=progress2`)[cite: 2]
        
    2. _Mirror Copy_ (`-arvzHP --info=progress2 --delete-after`)[cite: 2]
        
    3. _Custom Switches_ (User-entered string)[cite: 2]
        

### `write_audit_log()`

- **Purpose:** Enterprise compliance reporting[cite: 2].
    
- **Behavior:** Appends execution records containing operator ID (`whoami`), run timestamp, network metrics, and mapped path arrays into `AUDIT_LOG`[cite: 2].
    

## 4. Troubleshooting & Operational Notes

### Local Lock Error: `[ERROR] This migration script is ALREADY running on this server!`

- **Cause:** Another instance of `safe-rsync` is currently active, holding File Descriptor 9 on `/var/run/path_migration.lock`[cite: 2].
    
- **Resolution:** Check running instances using `ps aux | grep safe-rsync`. If a previous session crashed unexpectedly, ensure the lock file is released or remove `/var/run/path_migration.lock`.
    

### Custom Destination Path Structure Requirements

- **Note:** Ensure target directories exist on the destination server prior to migration. `check_destination_status()` will validate path existence and volume capacity before launching `rsync` background tasks[cite: 2].