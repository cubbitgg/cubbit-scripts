#!/bin/bash

# Header
echo "============================"
echo "Node Ephemeral Storage Usage"
echo "============================"
printf "%-45s | %-15s | %-15s | %-8s | %-15s\n" "NODE" "ALLOCATABLE" "USED" "PERCENT" "STATUS"

# Get all nodes
nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

for node in $nodes; do
  # Get allocatable ephemeral storage
  allocatable=$(kubectl get node $node -o jsonpath='{.status.allocatable.ephemeral-storage}')
  
  # Convert to human-readable format
  allocatable_bytes=$(echo $allocatable | sed 's/Ki/*1024/g; s/Mi/*1048576/g; s/Gi/*1073741824/g; s/Ti/*1099511627776/g' | bc)
  allocatable_hr=$(numfmt --to=iec --suffix=B $allocatable_bytes 2>/dev/null || echo "$allocatable")
  
  # Get node conditions
  diskpressure=$(kubectl get node $node -o jsonpath='{.status.conditions[?(@.type=="DiskPressure")].status}')
  
  # Set status based on disk pressure condition
  if [[ "$diskpressure" == "True" ]]; then
    status="DiskPressure"
  else
    status="OK"
  fi
  
  # Get used ephemeral storage using kubectl describe
  # Extract the line with "ephemeral-storage" and the percentage
  describe_output=$(kubectl describe node $node)
  ephemeral_line=$(echo "$describe_output" | grep -A 5 "Allocated resources" | grep "ephemeral-storage")
  
  if [[ -n "$ephemeral_line" ]]; then
    # Extract used and percentage values
    used=$(echo "$ephemeral_line" | awk '{print $2}')
    percent=$(echo "$ephemeral_line" | awk '{print $4}')
  else
    # Try alternative method - query kubelet API stats
    # Start kubectl proxy in background
    kubectl proxy &>/dev/null &
    proxy_pid=$!
    
    # Give it time to start
    sleep 2
    
    # Query node stats summary
    stats_json=$(curl -s http://localhost:8001/api/v1/nodes/$node/proxy/stats/summary)
    
    # Kill proxy
    kill $proxy_pid &>/dev/null
    
    # Extract filesystem usage if jq is available
    if command -v jq &>/dev/null && [[ -n "$stats_json" ]]; then
      used_bytes=$(echo "$stats_json" | jq -r '.node.fs.usedBytes // empty')
      capacity_bytes=$(echo "$stats_json" | jq -r '.node.fs.capacityBytes // empty')
      
      if [[ -n "$used_bytes" && -n "$capacity_bytes" && "$capacity_bytes" != "0" ]]; then
        used=$(numfmt --to=iec --suffix=B $used_bytes 2>/dev/null || echo "N/A")
        percent=$(echo "scale=1; $used_bytes * 100 / $capacity_bytes" | bc)
        percent="${percent}%"
      else
        used="N/A"
        percent="N/A"
      fi
    else
      used="N/A"
      percent="N/A"
    fi
  fi
  
  # Print the output
  printf "%-45s | %-15s | %-15s | %-8s | %-15s\n" "$node" "$allocatable_hr" "$used" "$percent" "$status"
done

echo -e "\nNote: 'USED' column may show N/A if node metrics are unavailable."
echo "For more accurate measurements, consider installing metrics-server or Prometheus."