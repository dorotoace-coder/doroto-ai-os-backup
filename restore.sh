#!/bin/bash

# Configuration
BACKUP_DIR="~/.doroto/ai-os-backup-recovery/backups"

# Ensure root privileges
if [ "$(id -un)" != "root" ]; then
    echo "This script must be run as root or with sudo."
    exit 1
fi

# Usage function
usage() {
    echo "Usage: $0 /path/to/backup.zip"
    echo "       $0 -l (list available backups)"
    exit 1
}

# List available backups
if [ "$1" == "-l" ]; then
    echo "Available backups in $BACKUP_DIR:"
    ls -lh "$BACKUP_DIR"/*.zip 2>/dev/null || echo "No backups found."
    exit 0
fi

# Check if a backup file is provided
if [ -z "$1" ]; then
    usage
fi

BACKUP_FILE="$1"

# Validate backup file
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found at $BACKUP_FILE"
    exit 1
fi

# Confirm with the user
echo "!!!!!! DANGER: This will overwrite your current AI-OS configuration. !!!!!!!!"
echo "Are you sure you want to restore from $BACKUP_FILE? (yes/no)"
read -p "> " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Restore cancelled."
    exit 0
fi

# Create a temporary directory for extraction
TEMP_EXTRACT_DIR="/tmp/ai-os-restore-$(date +"%Y%m%d%H%M%S")"
mkdir -p "$TEMP_EXTRACT_DIR"

# Extract the backup
echo "Extracting backup to $TEMP_EXTRACT_DIR..."
unzip -q "$BACKUP_FILE" -d "$TEMP_EXTRACT_DIR/extracted"

# Verify extraction
if [ $? -ne 0 ]; then
    echo "Error: Failed to extract backup file."
    rm -rf "$TEMP_EXTRACT_DIR"
    exit 1
fi

# Perform restoration
echo "Restoring files..."
cp -R "$TEMP_EXTRACT_DIR/extracted/tmp/ai-os-backup-*/openclaw_workspace" ~/.openclaw/
cp -R "$TEMP_EXTRACT_DIR/extracted/tmp/ai-os-backup-*/openclaw_agents" ~/.openclaw/
cp -R "$TEMP_EXTRACT_DIR/extracted/tmp/ai-os-backup-*/doroto" ~/
cp -R "$TEMP_EXTRACT_DIR/extracted/tmp/ai-os-backup-*/launchagents" ~/Library/

# Restore n8n workflows - This is more complex and might require manual import or specific API calls
# For simplicity, we'll just place the JSON file and assume manual import for now.
# A more advanced script would use n8n's import API.
N8N_RESTORE_FILE="$TEMP_EXTRACT_DIR/extracted/tmp/ai-os-backup-*/n8n_workflows.json"
if [ -f "$N8N_RESTORE_FILE" ]; then
    echo "n8n workflows backup found. Please manually import "$N8N_RESTORE_FILE" into n8n."
    echo "You can also try using the n8n API to import:"
    echo "curl -X POST http://localhost:5678/api/v1/workflows/import -H \"Content-Type: application/json\" -d @"$N8N_RESTORE_FILE""
fi

echo "
"Restore complete! Please manually verify all components and import n8n workflows if applicable.
Rebooting your system might be required for some changes to take full effect (e.g., launch agents).
"

# Clean up temporary extraction directory
rm -rf "$TEMP_EXTRACT_DIR"
