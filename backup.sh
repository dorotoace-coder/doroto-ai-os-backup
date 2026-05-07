#!/bin/bash
# ============================================================
# Doroto AI-OS Backup Script v2
# Fixed (2026-05-03):
#   - Tilde-in-quotes bug fixed (cp "~/.." → cp "$HOME/..")
#   - Each step fails independently — one failure doesn't kill the whole backup
#   - Telegram alert sent directly (no n8n dependency for notifications)
#   - Git push failure is non-fatal
#   - rclone failure is non-fatal
#   - Status report sent to Telegram with per-step results
# ============================================================

BACKUP_DIR="$HOME/.doroto/ai-os-backup-recovery/backups"
TARGET_REPO="git@github.com:dorotoace-coder/doroto-ai-os-backup.git"
SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
SECRETS_FILE="$HOME/.openclaw/secrets.env"
TEMP_BACKUP_PREFIX="ai-os-backup-$(date +"%Y%m%d%H%M%S")"
TEMP_BACKUP_DIR="/tmp/$TEMP_BACKUP_PREFIX"

# ---- Helpers -----------------------------------------------

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

read_secret() {
    python3 -c "import json,sys; d=json.load(open('${SECRETS_FILE}')); print(d.get('$1',''))" 2>/dev/null
}

alert_telegram() {
    local message="$1"
    local token chat_id
    token=$(read_secret telegram_token)
    chat_id="8461115583"
    if [[ -n "${token}" ]]; then
        curl -s "https://api.telegram.org/bot${token}/sendMessage" \
            --data-urlencode "chat_id=${chat_id}" \
            --data-urlencode "text=${message}" \
            --max-time 10 > /dev/null 2>&1
    fi
}

# ---- Setup -------------------------------------------------

mkdir -p "$BACKUP_DIR"
mkdir -p "$TEMP_BACKUP_DIR"
mkdir -p "$TEMP_BACKUP_DIR/launchagents"

STEP_FILES="❌"
STEP_N8N="⚠️ skipped"
STEP_ZIP="❌"
STEP_LOCAL="❌"
STEP_GDRIVE="⚠️ skipped"
STEP_GIT="⚠️ skipped"

# ---- Step 1: Archive files ---------------------------------

log "Step 1: Archiving directories..."
cp -R "$HOME/.openclaw/workspace/" "$TEMP_BACKUP_DIR/openclaw_workspace" 2>/dev/null && \
cp -R "$HOME/.openclaw/agents/" "$TEMP_BACKUP_DIR/openclaw_agents" 2>/dev/null && \
cp -R "$HOME/.doroto/" "$TEMP_BACKUP_DIR/doroto" 2>/dev/null && \
STEP_FILES="✅"

cp -R "$HOME/Library/LaunchAgents/ai.doroto."* "$TEMP_BACKUP_DIR/launchagents/" 2>/dev/null || true

if [[ "$STEP_FILES" == "❌" ]]; then
    log "ERROR: File archiving failed"
fi

# ---- Step 2: Export n8n workflows --------------------------

log "Step 2: Exporting n8n workflows..."
if curl -sf --max-time 5 "http://localhost:5678/healthz" > /dev/null 2>&1; then
    curl -s "http://localhost:5678/api/v1/workflows?all=true" \
        -H "Accept: application/json" \
        > "$TEMP_BACKUP_DIR/n8n_workflows.json" 2>/dev/null && \
    STEP_N8N="✅" || STEP_N8N="❌ export failed"
else
    STEP_N8N="⚠️ n8n offline"
    log "WARN: n8n not running — skipping workflow export"
fi

# ---- Step 3: Create zip ------------------------------------

BACKUP_FILE="${BACKUP_DIR}/${TEMP_BACKUP_PREFIX}.zip"
log "Step 3: Creating zip archive: $BACKUP_FILE"
zip -r -q "$BACKUP_FILE" "$TEMP_BACKUP_DIR" && STEP_ZIP="✅" || log "ERROR: zip failed"
rm -rf "$TEMP_BACKUP_DIR"

# ---- Step 4: Rotate local backups (keep 7) -----------------

log "Step 4: Rotating local backups..."
ls -t "$BACKUP_DIR"/*.zip 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null || true
STEP_LOCAL="✅ $(basename "$BACKUP_FILE")"

# ---- Step 5: Sync to Google Drive --------------------------

log "Step 5: Syncing to Google Drive..."
if command -v rclone > /dev/null 2>&1; then
    rclone copy "$BACKUP_FILE" "gdrive:Doroto-AI-OS-Backups/" \
        --fast-list --stats-one-line \
        --log-file="/tmp/rclone_$(date +"%Y%m%d%H%M%S").log" 2>/dev/null && \
    STEP_GDRIVE="✅" || STEP_GDRIVE="❌ rclone failed"
else
    STEP_GDRIVE="⚠️ rclone not installed"
    log "WARN: rclone not found — skipping Google Drive sync"
fi

# ---- Step 6: Push scripts to GitHub ------------------------

log "Step 6: Pushing scripts to GitHub..."
GIT_CLONE_DIR="/tmp/doroto-ai-os-scripts-repo"
rm -rf "$GIT_CLONE_DIR"

if GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH -o IdentitiesOnly=yes -o StrictHostKeyChecking=no" \
    git clone --depth 1 "$TARGET_REPO" "$GIT_CLONE_DIR" 2>/dev/null; then

    cp "$HOME/.doroto/ai-os-backup-recovery/backup.sh" "$GIT_CLONE_DIR/backup.sh" 2>/dev/null || true
    cp "$HOME/.doroto/ai-os-backup-recovery/restore.sh" "$GIT_CLONE_DIR/restore.sh" 2>/dev/null || true

    cd "$GIT_CLONE_DIR" || true
    git add backup.sh restore.sh 2>/dev/null || true

    if git diff --cached --exit-code --quiet 2>/dev/null; then
        STEP_GIT="✅ no changes"
    else
        git -c user.name='Doroto AI-OS Backup Bot' \
            -c user.email='backup@doroto.ai' \
            commit -m "Backup script update: $(date +"%Y-%m-%d %H:%M:%S")" 2>/dev/null && \
        GIT_SSH_COMMAND="ssh -i $SSH_KEY_PATH -o IdentitiesOnly=yes" \
            git push origin HEAD 2>/dev/null && \
        STEP_GIT="✅ pushed" || STEP_GIT="❌ push failed"
    fi
    rm -rf "$GIT_CLONE_DIR"
else
    STEP_GIT="⚠️ SSH/clone failed"
    log "WARN: GitHub clone failed — skipping script push"
fi

# ---- Step 7: Send Telegram summary -------------------------

SUMMARY="🗂 AI-OS Backup Report
$(date '+%Y-%m-%d %H:%M')

Files:    ${STEP_FILES}
n8n:      ${STEP_N8N}
Zip:      ${STEP_ZIP}
Local:    ${STEP_LOCAL}
GDrive:   ${STEP_GDRIVE}
GitHub:   ${STEP_GIT}"

log "Sending backup summary to Telegram..."
alert_telegram "$SUMMARY"
log "Backup complete."
log "$SUMMARY"
