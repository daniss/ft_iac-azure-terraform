#!/bin/bash
set -euo pipefail

ITERATIONS=${1:-1}
PAUSE_SECONDS=${2:-300}
LOG_FILE=${CHAOS_LOG:-chaos-monkey.log}

cd "$(dirname "$0")/azure-vm-terraform"

if ! command -v az >/dev/null 2>&1; then
  echo "Azure CLI (az) is required" >&2
  exit 1
fi

if ! command -v shuf >/dev/null 2>&1; then
  echo "shuf from coreutils is required" >&2
  exit 1
fi

RG_NAME=$(terraform output -raw resource_group_name)
VMSS_NAME=$(az vmss list -g "$RG_NAME" --query "[0].name" -o tsv)

if [[ -z "$VMSS_NAME" ]]; then
  echo "Unable to determine VMSS name in resource group $RG_NAME" >&2
  exit 1
fi

log() {
  local message="$1"
  echo "$(date -Is) $message" | tee -a "$LOG_FILE"
}

instance_count() {
  az vmss list-instances \
    --resource-group "$RG_NAME" \
    --name "$VMSS_NAME" \
    --query "length([?provisioningState=='Succeeded'])" \
    --output tsv
}

pick_instance() {
  az vmss list-instances \
    --resource-group "$RG_NAME" \
    --name "$VMSS_NAME" \
    --query "[].instanceId" \
    --output tsv | shuf -n 1
}

for ((i=1; i<=ITERATIONS; i++)); do
  log "Chaos iteration $i/$ITERATIONS"
  initial_count=$(instance_count)
  instance_id=$(pick_instance)

  if [[ -z "$instance_id" ]]; then
    log "No VMSS instance found; aborting"
    exit 1
  fi

  log "Deleting instance $instance_id (initial count: $initial_count)"
  start_ts=$(date +%s)
  az vmss delete-instances \
    --resource-group "$RG_NAME" \
    --name "$VMSS_NAME" \
    --instance-ids "$instance_id"

  log "Waiting for VMSS to recover..."
  while true; do
    sleep 15
    current_count=$(instance_count)
    if [[ "$current_count" -ge "$initial_count" ]]; then
      break
    fi
    log "  Recovery pending (current count: $current_count / $initial_count)"
  done

  duration=$(( $(date +%s) - start_ts ))
  log "Recovery complete in ${duration}s"

  if (( i < ITERATIONS )); then
    log "Sleeping ${PAUSE_SECONDS}s before next iteration"
    sleep "$PAUSE_SECONDS"
  fi

done

log "Chaos test finished"
