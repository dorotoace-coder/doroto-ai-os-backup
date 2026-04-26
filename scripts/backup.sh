#!/bin/bash

# Configuration
BACKUP_DIR="$HOME/.doroto/ai-os-backup-recovery/backups"
TARGET_REPO="git@github.com:dorotoace-coder/doroto-ai-os-backup.git"
SSH_KEY_PATH="$HOME/.ssh/id_ed25519"  # dorotoace-coder key (id_ed25519)
N8N_API_URL="http://localhost:5678/api/v1/workflows"
WEBHOOK_URL="http://localhost:5678/webhook/backup-status"  # WF-Backup: Status Notifier (ID: iZeDI1XtDaAXDVvK)

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Create a temporary directory for the current backup
TEMP_BACKUP_PREFIX="ai-os-backup-$(date +"%Y%m%d%H%M%S")"
TEMP_BACKUP_DIR="/tmp/$TEMP_BACKUP_PREFIX"
mkdir -p "$TEMP_BACKUP_DIR"

# 1. Backup specified directories
echo "Archiving directories..."
cp -R ~/.openclaw/workspace/ "$TEMP_BACKUP_DIR/openclaw_workspace"
cp -R ~/.openclaw/agents/ "$TEMP_BACKUP_DIR/openclaw_agents"
cp -R ~/.doroto/ "$TEMP_BACKUP_DIR/doroto"
cp -R ~/Library/LaunchAgents/ai.doroto.* "$TEMP_BACKUP_DIR/launchagents/" 2>/dev/null || : # Ignore if no launch agents exist

# 2. Backup n8n workflows via API
echo "Exporting n8n workflows..."
N8N_EXPORT_FILE="$TEMP_BACKUP_DIR/n8n_workflows.json"
curl -s ${N8N_API_URL}?all=true -H "Accept: application/json" > "$N8N_EXPORT_FILE"

# Create the final zip archive
BACKUP_FILE="${BACKUP_DIR}/${TEMP_BACKUP_PREFIX}.zip"
echo "Creating zip archive: $BACKUP_FILE"
zip -r "$BACKUP_FILE" "$TEMP_BACKUP_DIR" > /dev/null

# Clean up temporary backup directory
rm -rf "$TEMP_BACKUP_DIR"

# 3. Keep only the last 7 local backups
echo "Cleaning up old local backups..."
ls -t "$BACKUP_DIR"/*.zip | tail -n +8 | xargs rm -- {} 2>/dev/null || :

# 4. Push to GitHub repo
echo "Pushing to GitHub repository: $TARGET_REPO"
GIT_CLONE_DIR="/tmp/doroto-ai-os-backup-repo"
rm -rf "$GIT_CLONE_DIR"
git clone "$TARGET_REPO" "$GIT_CLONE_DIR" || { echo "Failed to clone repository."; exit 1; }

# Copy newly created zip to clone directory
cp "$BACKUP_FILE" "$GIT_CLONE_DIR/"

cd "$GIT_CLONE_DIR" || { echo "Failed to enter git clone directory."; exit 1; }

# Add changes, commit, and push
git add .
git -c user.name='Doroto AI-OS Backup Bot' -c user.email='backup@doroto.ai' commit -m "Automated AI-OS backup: $(date +"%Y-%m-%d %H:%M:%S")"
GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH -o IdentitiesOnly=yes" git push origin HEAD

if [ $? -eq 0 ]; then
    STATUS="✅ Backup successful: $(basename "$BACKUP_FILE")"
    echo "$STATUS"
else
    STATUS="❌ Backup failed for: $(basename "$BACKUP_FILE")"
    echo "$STATUS"
fi

# Send Telegram alert via n8n webhook
# Note: This requires an n8n workflow configured to receive this webhook and send a Telegram message.
# The webhook needs to be created in n8n and replaced above.
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"status\": \"$STATUS\", \"details\": \"$(date '+%Y-%m-%d %H:%M:%S') — $(hostname)\"}" \
  "$WEBHOOK_URL"

# Cleanup cloned repo
rm -rf "$GIT_CLONE_DIR"
