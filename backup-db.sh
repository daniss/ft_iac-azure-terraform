#!/bin/bash
set -euo pipefail

RESTORE_DELAY_MINUTES=${RESTORE_DELAY_MINUTES:-10}
KEEP_BACKUP_SERVER=${KEEP_BACKUP_SERVER:-false}
LOG_FILE=${BACKUP_LOG:-backup-history.log}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/azure-vm-terraform"

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI (az) is required" >&2
  exit 1
fi

log() {
  local msg="$1"
  echo "$(date -Is) $msg" | tee -a "$SCRIPT_DIR/$LOG_FILE"
}

RG_NAME=$(terraform output -raw resource_group_name)
SERVER_NAME=$(az mysql flexible-server list -g "$RG_NAME" --query "[0].name" -o tsv)

if [[ -z "$SERVER_NAME" ]]; then
  echo "Unable to determine MySQL flexible server name" >&2
  exit 1
fi

RESTORE_TIME=$(date -u -d "-$RESTORE_DELAY_MINUTES minutes" +"%Y-%m-%dT%H:%M:%SZ")
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
TARGET_NAME=$(printf "%s" "${SERVER_NAME}-bak-${TIMESTAMP}" | cut -c1-63)

log "Triggering point-in-time restore to $TARGET_NAME (restore time: $RESTORE_TIME)"
az mysql flexible-server restore \
  --resource-group "$RG_NAME" \
  --name "$TARGET_NAME" \
  --source-server "$SERVER_NAME" \
  --restore-time "$RESTORE_TIME" \
  --yes

log "Waiting for restored server to become Ready"
while true; do
  STATUS=$(az mysql flexible-server show \
    --resource-group "$RG_NAME" \
    --name "$TARGET_NAME" \
    --query "userVisibleState" \
    -o tsv 2>/dev/null || echo "Pending")

  if [[ "$STATUS" == "Ready" ]]; then
    break
  fi
  sleep 15
  log "  Status: $STATUS"
done

log "Restore completed; snapshot server $TARGET_NAME is ready"

if [[ "$KEEP_BACKUP_SERVER" != "true" ]]; then
  log "Deleting snapshot server $TARGET_NAME (set KEEP_BACKUP_SERVER=true to keep it)"
  az mysql flexible-server delete \
    --resource-group "$RG_NAME" \
    --name "$TARGET_NAME" \
    --yes \
    --force
  log "Snapshot server deleted"
else
  log "Snapshot server retained for manual verification"
fi

log "Backup workflow finished"
