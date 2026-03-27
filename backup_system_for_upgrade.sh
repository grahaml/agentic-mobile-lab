#!/bin/bash

# Configuration
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_ROOT="/media/grahaml/easystore1/BACKUPS/MACBUNTU/$DATE"
LOG_FILE="/tmp/backup-macbuntu-$DATE.log"

# Sources to include
SOURCES=(
    "/home/grahaml"
    "/etc"
    "/root"
    "/var/lib/rancher/k3s"
    "/usr/local/bin"
    "/opt"
)

# Exclusions (common cache and temp folders)
EXCLUDES=(
    "**/node_modules"
    "**/.cache"
    "**/tmp"
    "**/.local/share/Trash"
    "**/.BitwigStudio"
    "**/.asdf"
    "/var/lib/rancher/k3s/agent/containerd" # Optional: Skip large containerd layers if they aren't critical for restore
)

# Create backup directory
mkdir -p "$BACKUP_ROOT"

echo "Starting backup to $BACKUP_ROOT" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"

# Prepare exclusions for rsync
RSYNC_EXCLUDES=""
for item in "${EXCLUDES[@]}"; do
    RSYNC_EXCLUDES="$RSYNC_EXCLUDES --exclude='$item'"
done

# Run rsync
# -r: recursive
# -t: preserve modification times
# -v: verbose
# -P: progress and partial (allows resume)
# -H: preserve hard links
# --modify-window=1: helps with NTFS time precision
# --no-perms: NTFS doesn't support Linux permissions well
# --numeric-ids: helpful for restoring to a fresh install

for SRC in "${SOURCES[@]}"; do
    if [ -d "$SRC" ] || [ -f "$SRC" ]; then
        echo "Backing up $SRC..." | tee -a "$LOG_FILE"
        # We use eval to handle the dynamic exclude string properly
        eval "rsync -rtvPH --modify-window=1 --no-perms --numeric-ids $RSYNC_EXCLUDES \"$SRC\" \"$BACKUP_ROOT\" >> \"$LOG_FILE\" 2>&1"
    else
        echo "Warning: Source $SRC not found, skipping." | tee -a "$LOG_FILE"
    fi
done


echo "Backup complete! Logs are at $LOG_FILE" | tee -a "$LOG_FILE"
