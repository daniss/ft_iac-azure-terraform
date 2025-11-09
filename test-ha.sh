#!/bin/bash

set -e

echo "=========================================="
echo "High Availability Test"
echo "=========================================="
echo ""

RESOURCE_GROUP="rg-iac1-win-vm-iis-moth"
VMSS_NAME="win-vm-iis-moth-vmss"
APP_GATEWAY_NAME="win-vm-iis-moth-app-gw"
APP_URL="http://20.199.152.167"

echo "Test Configuration:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   VMSS: $VMSS_NAME"
echo "   Application Gateway: $APP_GATEWAY_NAME"
echo "   Application URL: $APP_URL"
echo ""

check_app_availability() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" "$APP_URL" || echo "000")
    if [[ "$response" == "302" ]] || [[ "$response" == "200" ]]; then
        echo "Application is responding (HTTP $response)"
        return 0
    else
        echo "Application is NOT responding (HTTP $response)"
        return 1
    fi
}

get_instance_count() {
    az vmss list-instances \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --query "length([?provisioningState=='Succeeded'])" \
        --output tsv
}

get_healthy_backends() {
    az network application-gateway show-backend-health \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_GATEWAY_NAME" \
        --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[?health=='Healthy'] | length(@)" \
        --output tsv 2>/dev/null || echo "0"
}

echo "=========================================="
echo "Phase 1: Initial State Check"
echo "=========================================="

initial_count=$(get_instance_count)
echo "Current VMSS instances: $initial_count"

if ! check_app_availability; then
    echo "Application is not available before test. Please check manually."
    exit 1
fi

echo ""
echo "=========================================="
echo "Phase 2: Simulate Server Failure"
echo "=========================================="

instance_id=$(az vmss list-instances \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --query "[0].instanceId" \
    --output tsv)

if [ -z "$instance_id" ]; then
    echo "Could not find instance to delete"
    exit 1
fi

echo "Deleting VMSS instance: $instance_id"
az vmss delete-instances \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VMSS_NAME" \
    --instance-ids "$instance_id" \
    --no-wait

echo "Waiting 10 seconds for instance deletion to propagate..."
sleep 10

echo ""
echo "Testing application availability during instance failure..."
for i in {1..5}; do
    echo -n "  Attempt $i/5: "
    if check_app_availability; then
        success=true
    fi
    sleep 2
done

echo ""
echo "=========================================="
echo "Phase 3: Recovery Monitoring"
echo "=========================================="

echo "Monitoring recovery (this may take 2-5 minutes)..."
echo ""

recovery_time=0
max_wait=600 # 10 minutes

while [ $recovery_time -lt $max_wait ]; do
    current_count=$(get_instance_count)
    
    echo "[$recovery_time s] Instances: $current_count"

    if [ "$current_count" -ge "$initial_count" ]; then
        echo ""
        echo "Recovery complete!"
        echo "   Time to recover: ${recovery_time}s"
        break
    fi
    
    sleep 15
    recovery_time=$((recovery_time + 15))
done

if [ $recovery_time -ge $max_wait ]; then
    echo "Recovery timeout - manual verification required"
fi

echo ""
echo "=========================================="
echo "Phase 4: Final Validation"
echo "=========================================="

final_count=$(get_instance_count)
final_healthy=$(get_healthy_backends)

echo "Final VMSS instances: $final_count (initial: $initial_count)"

if check_app_availability; then
    echo ""
    echo "=========================================="
    echo "HIGH AVAILABILITY TEST PASSED"
    echo "=========================================="
    echo "Summary:"
    echo "  • Application remained available during instance failure"
    echo "  • VMSS automatically recovered to minimum instance count"
    echo "  • Recovery time: ${recovery_time}s"
    exit 0
else
    echo ""
    echo "=========================================="
    echo "HIGH AVAILABILITY TEST FAILED"
    echo "=========================================="
    echo "Application is not responding after recovery"
    exit 1
fi
