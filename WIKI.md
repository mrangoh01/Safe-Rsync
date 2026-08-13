This page contains detailed function specs, execution flow diagrams, operational recommendations, and troubleshooting guidance.

## 1. Functions Diagram
```text
+-----------------------------------------------------------------------+
|                             MAIN EXECUTION                            |
+-----------------------------------------------------------------------+
                                    |
                                    v
                       +-------------------------+
                       | check_ssh_connection()  |
                       +-------------------------+
                                    |
                                    v
                       +-------------------------+
                       |  check_remote_rsync()   |
                       +-------------------------+
                                    |
                                    v
                       +-------------------------+
                       |   check_remote_lsof()   |
                       +-------------------------+
                                    |
                                    v
                       +-------------------------+
                       | check_source_volumes()  |
                       +-------------------------+
                                    |
                                    v
                       +-------------------------+
                       |check_destination_status()|
                       +-------------------------+
                                    |
                                    v
                       +-------------------------+
                       |configure_rsync_switches()|
                       +-------------------------+
                                    |
                                    v
                       +-------------------------+
                       |   execute_migration()   |
                       +-------------------------+
```

## 2. Functions Descriptions

### `fail()`

- **Purpose:** Centralized error-handling routine.
    
- **Behavior:** Prints a formatted red error message to standard error and halts script execution with status code `1`.
    

### `wait_for_user()`

- **Purpose:** Interactive execution step control.
    
- **Behavior:** Pauses execution and prompts the user to press `ENTER` to proceed or `CTRL+C` to abort.
    

### `check_ssh_connection()`

- **Purpose:** Network and SSH authentication validation.
    
- **Behavior:** Executes a remote non-interactive command (`ssh -o ConnectTimeout=10 ... "echo 'SSH_OK'"`) to verify reachability and credential validity.
    

### `check_remote_rsync()`

- **Purpose:** Process-level conflict audit via `ps`.
    
- **Behavior:** Queries destination process list for active `rsync` instances. Compares active command-line arguments against configured `PATHS`. Aborts if target path overlap is detected; prompts for user confirmation on non-conflicting `rsync` tasks.
    

### `check_remote_lsof()`

- **Purpose:** File-handle lock audit via `lsof`.
    
- **Behavior:** Executes `lsof +D` on destination target directories. Detects active file locks, logs lock details to `dst_processes.log`, and prompts or aborts based on severity.
    

### `check_source_volumes()`

- **Purpose:** Local directory inspection.
    
- **Behavior:** Iterates over local paths, calculates disk usage (`du -sh`), and displays a summary table.
    

### `check_destination_status()`

- **Purpose:** Remote mount and disk capacity verification.
    
- **Behavior:** Verifies directory presence and mount status (`mountpoint -q`) on target host. Extracts remote free space (`df -P`), compares against local dataset size, and aborts if destination capacity is insufficient.
    

### `configure_rsync_switches()`

- **Purpose:** Dynamic flag assembly.
    
- **Behavior:** Interactively queries whether to append `--delete-after` to the baseline `DEFAULT_SWITCHES`.
    

### `execute_migration()`

- **Purpose:** Background job orchestration.
    
- **Behavior:** Launches `rsync` transfers in the background (`&`), redirects output streams to `rsync_output.log`, records task PIDs into `rsync_proc.pid`, and returns terminal control to the user.
    

## 3. Usage Suggestions & Modularity

### Customizing Execution Steps

`safe-rsync` is modular. You can bypass specific check steps in automated environments or when certain remote tools (e.g., `lsof`) are unavailable:

- **Bypassing `lsof` check:** If the destination system lacks `lsof` privileges, comment out `check_remote_lsof` in the main execution block:
```bash
check_ssh_connection
check_remote_rsync
# check_remote_lsof   # Bypassed
check_source_volumes
check_destination_status
configure_rsync_switches
execute_migration
```

**Fully Unattended / Non-Interactive Execution:** To run `safe-rsync` via cron or CI/CD pipelines, disable `wait_for_user` calls and pre-set default switches in script configurations.

### Suggested Rsync Switches

|**Switch**|**Purpose**|
|---|---|
|`-a` (`--archive`)|Enables archive mode; preserves permissions, timestamps, symlinks, owners, and groups.|
|`-r` (`--recursive`)|Recurses into directories.|
|`-v` (`--verbose`)|Increases verbosity output during transfers.|
|`-z` (`--compress`)|Compresses file data during transfer to minimize bandwidth usage.|
|`-H` (`--hard-links`)|Preserves hard links on destination.|
|`-P` (`--partial --progress`)|Keeps partially transferred files and shows progress metrics.|
|`--info=progress2`|Provides clean, single-line overall transfer statistics.|
|`--bwlimit=KBPS`|Restricts socket I/O bandwidth usage to specified kilobytes per second.|
|`--delete-after`|Deletes receiver-side files not present in sender path _after_ transfers complete.|
|`--checksum` (`-c`)|Forces file comparison via MD5/XXH64 checksums rather than modification time and size.|

## 4. Troubleshooting and FAQ

### Q1: Connection times out during `check_ssh_connection`.

- **Cause:** Firewall blocking port, incorrect `SSH_PORT`, or missing SSH key.
    
- **Fix:** Verify host reachability via `ping <IP>`, check SSH port binding, and test key authentication manually:
```bash
ssh -i /path/to/key -p PORT USER@IP
```

### Q2: `check_destination_status` fails with "NOT_MOUNTED".

- **Cause:** Target directory path resides under `/disks/*` but is not actively mounted.
    
- **Fix:** Mount the external block device on the destination host before running the migration:
```bash
ssh root@<DST_IP> "mount /dev/sdX /disks/target-disk"
```

### Q3: Script halts due to active `lsof` locks.

- **Cause:** Another process (e.g., web server, database, or active backup agent) is writing to the target directory.
    
- **Fix:** Review `dst_processes.log` on the source host to identify locking PIDs, then stop those services on the remote server before retrying.
    

### Q4: How do I terminate background migrations started by `safe-rsync`?

- **Fix:** Read the recorded PIDs from `rsync_proc.pid` and terminate them:
```bash
awk -F'PID=' '{print $2}' rsync_proc.pid | awk '{print $1}' | xargs kill -9
```

## 5. Script Analysis & Optimization Suggestions

### Identified Vulnerabilities & Recommended Improvements

1. **Missing Color Definition (`CYAN`):**
    
    - _Issue:_ In `check_remote_lsof`, the script references `${CYAN}`, but it is undefined in `CONFIGURATIONS`.
        
    - _Fix:_ Add `CYAN='\033[0;36m'` to the header block.
        
2. **Parallel Background Execution Risks:**
    
    - _Issue:_ The loop in `execute_migration` spawns every path transfer concurrently using `&`. If transfer sets are large, parallel IOPS and network requests can degrade performance or trigger destination file locks.
        
    - _Fix:_ Introduce a sequential execution toggle or job queue concurrency cap (`xargs -P` or GNU `parallel`).
        
3. **Wildcard Quote Escaping in `rsync` Command:**
    
    - _Issue:_ Passing `"$path_pattern"` wrapped in quotes to `rsync` prevents local wildcard expansion under certain shell conditions.
        
    - _Fix:_ Separate base directory paths from filename match patterns or handle expansion explicitly prior to calling `rsync`.
        
4. **Escaping Path Names containing Spaces:**
    
    - _Issue:_ Unescaped directory paths passed via remote SSH strings can cause syntax errors when paths contain whitespace or special characters.
        
    - _Fix:_ Sanitize paths using `printf '%q'` when injecting variable strings into remote SSH commands. """