#!/bin/bash

# Function to convert bytes to human readable format
bytes_to_human() {
  local bytes=$1
  if [[ -z "$bytes" || "$bytes" == "null" ]]; then
    echo "N/A"
    return
  fi
  
  numfmt --to=iec --suffix=B $bytes 2>/dev/null || echo "${bytes}B"
}

# Header
echo "============================"
    echo "Node Ephemeral Storage Usage"
echo "============================"
printf "%-45s | %-12s | %-12s | %-12s | %-8s | %-10s | %-14s | %-14s\n" "NODE" "STATUS" "FS_CAPACITY" "FS_AVAILABLE" "FS_USED%" "FS_USED" "FS_IMAGE_USED" "FS_CONTAINER_USED"

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
      fs_used_bytes=$(echo "$stats_json" | jq -r '.node.fs.usedBytes // empty')
      fs_capacity_bytes=$(echo "$stats_json" | jq -r '.node.fs.capacityBytes // empty')
      fs_available_bytes=$(echo "$stats_json" | jq -r '.node.fs.availableBytes // empty')
      
      fs_used=$(bytes_to_human "$fs_used_bytes")
      fs_used_percent=$(echo "scale=1; $fs_used_bytes * 100 / $fs_capacity_bytes" | bc)
      fs_capacity=$(bytes_to_human "$fs_capacity_bytes")
      fs_available=$(bytes_to_human "$fs_available_bytes")


      rt_image_used_bytes=$(echo "$stats_json" | jq -r '.node.runtime.imageFs.usedBytes // empty')
      rt_image_capacity_bytes=$(echo "$stats_json" | jq -r '.node.runtime.imageFs.capacityBytes // empty')
      rt_image_available_bytes=$(echo "$stats_json" | jq -r '.node.runtime.imageFs.availableBytes // empty')

      rt_image__used=$(bytes_to_human "$rt_image_used_bytes")
      rt_image__capacity=$(bytes_to_human "$rt_image_capacity_bytes")
      rt_image__available=$(bytes_to_human "$rt_image_available_bytes")

      rt_container_used_bytes=$(echo "$stats_json" | jq -r '.node.runtime.containerFs.usedBytes // empty')
      rt_container_capacity_bytes=$(echo "$stats_json" | jq -r '.node.runtime.containerFs.capacityBytes // empty')
      rt_container_available_bytes=$(echo "$stats_json" | jq -r '.node.runtime.containerFs.availableBytes // empty')

      rt_container__used=$(bytes_to_human "$rt_container_used_bytes")
      rt_container__capacity=$(bytes_to_human "$rt_container_capacity_bytes")
      rt_container__available=$(bytes_to_human "$rt_container_available_bytes")

#      if [[ -n "$used_bytes" && -n "$capacity_bytes" && "$capacity_bytes" != "0" ]]; then
#        used=$(numfmt --to=iec --suffix=B $used_bytes 2>/dev/null || echo "N/A")
#        percent=$(echo "scale=1; $used_bytes * 100 / $capacity_bytes" | bc)
#        percent="${percent}%"
#      else
#        used="N/A"
#        percent="N/A"
#      fi
    else
      used="N/A"
      percent="N/A"
    fi
  fi
  
  # Print the output
  printf "%-45s | %-12s | %-12s | %-12s | %-8s | %-10s | %-14s | %-14s\n" "$node" "$status" "$fs_capacity" "$fs_available" "$fs_used_percent" "$fs_used" "$rt_image__used" "$rt_container__used"
done

echo -e "\nNote: 'USED' column may show N/A if node metrics are unavailable."
echo "For more accurate measurements, consider installing metrics-server or Prometheus."