#!/bin/bash

# Scalability Test Script
# Tests: CPU-based autoscaling by generating load

set -e

echo "=========================================="
echo "Scalability / Autoscaling Test"
echo "=========================================="
echo ""

RESOURCE_GROUP="rg-iac1-win-vm-iis-moth"
VMSS_NAME="win-vm-iis-moth-vmss"
APP_URL="http://20.199.152.167"
LOAD_DURATION=300
THREADS=50  # Increased from 10 to 50 for higher CPU load

echo "Test Configuration:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   VMSS: $VMSS_NAME"
echo "   Application URL: $APP_URL"
echo "   Load Duration: ${LOAD_DURATION}s ($(($LOAD_DURATION / 60)) minutes)"
echo "   Concurrent Threads: $THREADS"
echo ""

if ! command -v ab &> /dev/null && ! command -v wrk &> /dev/null; then
    echo "No load testing tool found. Installing apache2-utils (ab)..."
    sudo apt-get update -qq && sudo apt-get install -y apache2-utils
fi

get_instance_count() {
    az vmss list-instances \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --query "length([?provisioningState=='Succeeded'])" \
        --output tsv
}

get_average_cpu() {
    az monitor metrics list \
        --resource "/subscriptions/680182c5-659b-43f7-b6da-80b3abe9fdea/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachineScaleSets/$VMSS_NAME" \
        --metric "Percentage CPU" \
        --interval PT1M \
        --query "value[0].timeseries[0].data[-1].average" \
        --output tsv 2>/dev/null || echo "0"
}

echo "=========================================="
echo "Phase 1: Baseline Measurement"
echo "=========================================="

baseline_count=$(get_instance_count)
echo "Initial instance count: $baseline_count"

baseline_cpu=$(get_average_cpu)
echo "Initial CPU usage: ${baseline_cpu}%"

echo ""
echo "=========================================="
echo "Phase 2: Generate Load"
echo "=========================================="

echo "Starting load generation for $LOAD_DURATION seconds..."
echo "   This will make many requests to trigger CPU-based autoscaling"
echo ""

# Run load test in background
if command -v ab &> /dev/null; then
    echo "Using Apache Bench (ab) for load testing..."
    total_requests=$((LOAD_DURATION * 100))
    ab -n $total_requests -c $THREADS -t $LOAD_DURATION "$APP_URL/" > /tmp/load-test.log 2>&1 &
    LOAD_PID=$!
elif command -v wrk &> /dev/null; then
    echo "Using wrk for load testing..."
    wrk -t$THREADS -c$THREADS -d${LOAD_DURATION}s "$APP_URL/" > /tmp/load-test.log 2>&1 &
    LOAD_PID=$!
else
    echo "No load testing tool available. Using curl in loop..."
    # Fallback to curl loop
    for i in $(seq 1 $THREADS); do
        (
            end_time=$(($(date +%s) + LOAD_DURATION))
            while [ $(date +%s) -lt $end_time ]; do
                curl -s "$APP_URL" > /dev/null
            done
        ) &
    done
    LOAD_PID=$!
fi

echo "Load generation started (PID: $LOAD_PID)"
echo ""

echo "=========================================="
echo "Phase 3: Monitor Scaling Activity"
echo "=========================================="

echo "Monitoring CPU and instance count (every 30s)..."
echo ""
printf "%-10s %-15s %-15s %-10s\n" "Time (s)" "Instances" "Avg CPU (%)" "Status"
echo "-----------------------------------------------------------"

monitoring_time=0
max_instances=$baseline_count
scale_up_detected=false

while [ $monitoring_time -lt $LOAD_DURATION ]; do
    current_count=$(get_instance_count)
    current_cpu=$(get_average_cpu)
    
    if [ "$current_count" -gt "$max_instances" ]; then
        max_instances=$current_count
        scale_up_detected=true
    fi
    
    if [ "$current_count" -gt "$baseline_count" ]; then
        status="SCALING UP"
    elif [ "$current_count" -eq "$baseline_count" ]; then
        status="STABLE"
    else
        status="SCALING DOWN"
    fi
    
    printf "%-10s %-15s %-15s %-10s\n" "$monitoring_time" "$current_count" "$current_cpu" "$status"
    
    sleep 30
    monitoring_time=$((monitoring_time + 30))
done

# Ensure load test is stopped
kill $LOAD_PID 2>/dev/null || true
echo ""
echo "Load generation stopped"

echo ""
echo "=========================================="
echo "Phase 4: Monitor Scale Down"
echo "=========================================="

echo "Monitoring scale-down activity (5 minutes)..."
echo ""

cooldown_time=0
cooldown_max=300

while [ $cooldown_time -lt $cooldown_max ]; do
    current_count=$(get_instance_count)
    current_cpu=$(get_average_cpu)
    
    printf "%-10s %-15s %-15s\n" "$cooldown_time" "$current_count" "$current_cpu"
    
    if [ "$current_count" -eq "$baseline_count" ]; then
        echo ""
        echo "Scaled back to baseline ($baseline_count instances)"
        break
    fi
    
    sleep 30
    cooldown_time=$((cooldown_time + 30))
done

echo ""
echo "=========================================="
echo "Test Results"
echo "=========================================="

final_count=$(get_instance_count)

echo "Baseline instances: $baseline_count"
echo "Maximum instances during load: $max_instances"
echo "Final instances: $final_count"
echo ""

if [ "$scale_up_detected" = true ]; then
    scale_up_count=$((max_instances - baseline_count))
    echo "AUTOSCALING TEST PASSED"
    echo ""
    echo "Summary:"
    echo "  • Autoscaling triggered successfully"
    echo "  • Scaled up by: $scale_up_count instance(s)"
    echo "  • Maximum capacity reached: $max_instances instances"
    echo "  • CPU-based scaling rule is working"
    
    if [ "$final_count" -eq "$baseline_count" ]; then
        echo "  • Successfully scaled back down to baseline"
    else
        echo "  • Scale-down in progress (currently at $final_count instances)"
    fi
    
    echo ""
    echo "Load test results saved to: /tmp/load-test.log"
    exit 0
else
    echo "AUTOSCALING TEST WARNING"
    echo ""
    echo "No scale-up detected. Possible reasons:"
    echo "  • Load was not high enough to trigger CPU threshold (>75%)"
    echo "  • Autoscaling rule may need adjustment"
    echo "  • Instances may be over-provisioned for the load"
    echo ""
    echo "Current instance count: $final_count"
    echo "Maximum instance count: $max_instances"
    echo ""
    echo "To trigger scaling, you may need to:"
    echo "  1. Increase THREADS value in the script"
    echo "  2. Increase LOAD_DURATION to sustain high CPU"
    echo "  3. Lower autoscaling CPU threshold in Terraform"
    exit 1
fi
