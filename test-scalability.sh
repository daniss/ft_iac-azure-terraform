#!/bin/bash

set -e

cd azure-vm-terraform
RG_NAME=$(terraform output -raw resource_group_name)
VMSS_NAME=$(az vmss list -g "$RG_NAME" --query "[0].name" -o tsv)

for INSTANCE_ID in $(az vmss list-instances -g "$RG_NAME" -n "$VMSS_NAME" --query "[].instanceId" -o tsv); do
    echo "Stressing instance $INSTANCE_ID..."
    az vmss run-command invoke \
      --resource-group "$RG_NAME" \
      --name "$VMSS_NAME" \
      --instance-id "$INSTANCE_ID" \
      --command-id RunShellScript \
      --scripts "sudo apt-get update && sudo apt-get install -y stress-ng && stress-ng --cpu 0 --timeout 720s" &
done

wait
echo "All stress tests launched! Check Azure Portal metrics in 5-10 minutes."