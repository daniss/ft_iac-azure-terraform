#!/bin/bash

set -e

cd azure-vm-terraform
RG_NAME=$(terraform output -raw resource_group_name)
SERVER_NAME=$(az mysql flexible-server list -g $RG_NAME --query "[0].name" -o tsv)

echo "=== Database Backup Information ==="
echo ""
echo "Resource Group: $RG_NAME"
echo "Server: $SERVER_NAME"
echo ""

# Show backup details
az mysql flexible-server show \
  --resource-group $RG_NAME \
  --name $SERVER_NAME \
  --query "{EarliestRestore:earliestRestoreDate, RetentionDays:backup.backupRetentionDays, GeoBackup:backup.geoRedundantBackup}" \
  -o table

echo ""
echo "=== Restore Commands ==="
echo ""
echo "Point-in-time restore (last 7 days):"
echo "  az mysql flexible-server restore \\"
echo "    --resource-group $RG_NAME \\"
echo "    --name ${SERVER_NAME}-restored \\"
echo "    --source-server $SERVER_NAME \\"
echo "    --restore-time '2025-11-09T10:00:00Z'"
echo ""
echo "Geo-restore to another region:"
echo "  az mysql flexible-server geo-restore \\"
echo "    --resource-group $RG_NAME \\"
echo "    --name ${SERVER_NAME}-geo \\"
echo "    --source-server $SERVER_NAME \\"
echo "    --location westeurope"
echo ""
