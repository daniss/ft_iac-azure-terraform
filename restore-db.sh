#!/bin/bash
set -e

echo "=== Azure MySQL Database Restore Tool ==="
echo ""

cd azure-vm-terraform
RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null)

if [ -z "$RG_NAME" ]; then
    echo "Error: Could not get resource group name from terraform output"
    echo "Make sure terraform has been applied successfully"
    exit 1
fi

SERVER_NAME=$(az mysql flexible-server list -g $RG_NAME --query "[0].name" -o tsv 2>/dev/null)

if [ -z "$SERVER_NAME" ]; then
    echo "Error: Could not find MySQL server in resource group $RG_NAME"
    exit 1
fi

echo "Resource Group: $RG_NAME"
echo "MySQL Server: $SERVER_NAME"
echo ""

# Show backup information
echo "Backup Information:"
az mysql flexible-server show \
  --resource-group $RG_NAME \
  --name $SERVER_NAME \
  --query "{EarliestRestoreDate:earliestRestoreDate, BackupRetentionDays:backup.backupRetentionDays, GeoRedundantBackup:backup.geoRedundantBackup}" \
  -o table

echo ""
echo "Select restore type:"
echo "  1) Point-in-Time Restore (restore to a specific time in the last 7 days)"
echo "  2) Geo-Restore (restore from geo-redundant backup to different region)"
echo "  3) Show current backups info only"
echo ""
read -p "Enter your choice [1-3]: " CHOICE

case $CHOICE in
    1)
        echo ""
        echo "Point-in-Time Restore selected"
        echo "Format: YYYY-MM-DDTHH:MM:SSZ (UTC timezone)"
        echo "Example: 2024-11-09T10:30:00Z"
        echo ""
        read -p "Enter restore time: " RESTORE_TIME
        
        if [ -z "$RESTORE_TIME" ]; then
            echo "Error: Restore time cannot be empty"
            exit 1
        fi
        
        NEW_SERVER="${SERVER_NAME}-restored-$(date +%Y%m%d-%H%M%S)"
        
        echo ""
        echo "Restoring database to $RESTORE_TIME..."
        echo "New server name: $NEW_SERVER"
        echo ""
        
        az mysql flexible-server restore \
          --resource-group $RG_NAME \
          --name $NEW_SERVER \
          --source-server $SERVER_NAME \
          --restore-time "$RESTORE_TIME"
        
        echo ""
        echo "Restore completed successfully!"
        echo ""
        echo "New server details:"
        az mysql flexible-server show \
          --resource-group $RG_NAME \
          --name $NEW_SERVER \
          --query "{Name:name, FQDN:fullyQualifiedDomainName, State:state}" \
          -o table
        ;;
        
    2)
        echo ""
        echo "Geo-Restore selected"
        echo "Available regions: westeurope, northeurope, eastus, westus, switzerlandnorth"
        echo ""
        read -p "Enter target region: " REGION
        
        if [ -z "$REGION" ]; then
            echo "Error: Region cannot be empty"
            exit 1
        fi
        
        NEW_SERVER="${SERVER_NAME}-georestored"
        
        echo ""
        echo "Performing geo-restore to region: $REGION..."
        echo "New server name: $NEW_SERVER"
        echo ""
        
        az mysql flexible-server geo-restore \
          --resource-group $RG_NAME \
          --name $NEW_SERVER \
          --source-server $SERVER_NAME \
          --location $REGION
        
        echo ""
        echo "Geo-restore completed successfully!"
        echo ""
        echo "New server details:"
        az mysql flexible-server show \
          --resource-group $RG_NAME \
          --name $NEW_SERVER \
          --query "{Name:name, FQDN:fullyQualifiedDomainName, Location:location, State:state}" \
          -o table
        ;;
        
    3)
        echo ""
        echo "Current backup status:"
        az mysql flexible-server show \
          --resource-group $RG_NAME \
          --name $SERVER_NAME \
          --query "{Name:name, EarliestRestoreDate:earliestRestoreDate, BackupRetention:backup.backupRetentionDays, GeoBackup:backup.geoRedundantBackup, Location:location}" \
          -o table
        echo ""
        echo "You can restore to any point between the earliest restore date and now."
        ;;
        
    *)
        echo "Invalid choice. Please run the script again and select 1, 2, or 3."
        exit 1
        ;;
esac

echo ""
echo "Done!"
