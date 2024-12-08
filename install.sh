#!/bin/bash

# Function to get drive type (USB or DISK)
get_drive_type() {
    local device=$1
    if udevadm info --query=property "/dev/$device" | grep -q "ID_BUS=usb"; then
        echo "USB"
    else
        echo "DISK"
    fi
}

# Function to get drive's by-id path
get_drive_by_id() {
    local device=$1
    local by_id
    
    # Get the first non-wwn, non-nvme-eui persistent name for the device
    by_id=$(readlink -f "/dev/$device")
    by_id=$(ls -l /dev/disk/by-id | grep -v wwn | grep -v nvme-eui | grep -w "$by_id" | head -n1 | awk '{print $9}')
    
    if [ -z "$by_id" ]; then
        echo "disk-$device"
    else
        echo "$by_id"
    fi
}

# Function to get size in a consistent format
get_size() {
    local device=$1
    lsblk -dbn -o SIZE "/dev/$device" | numfmt --to=iec-i --suffix=B
}

# Function to get all available drives and format them for whiptail
get_drive_list() {
    local drive_list=()
    
    while IFS= read -r device; do
        # Skip loop devices and installation media
        if [[ ! $device =~ ^loop && ! $device =~ ^sr ]]; then
            local by_id=$(get_drive_by_id "$device")
            local size=$(get_size "$device")
            local type=$(get_drive_type "$device")
            
            # Format with fixed-width columns
            # Add extra spaces for padding between columns
            drive_list+=("$by_id" "$(printf '%-10s %-6s' "$size" "[$type]")" "off")
        fi
    done < <(lsblk -dn -o NAME)
    
    echo "${drive_list[@]}"
}

# Get terminal dimensions
TERM_HEIGHT=$(tput lines)
TERM_WIDTH=$(tput cols)

# Calculate whiptail window dimensions
WHIP_HEIGHT=$((TERM_HEIGHT - 8))
WHIP_WIDTH=$((TERM_WIDTH - 10))

# Create temporary files for storing selections
TMP_DRIVES=$(mktemp)
TMP_POOL=$(mktemp)

# Get the drive list array
DRIVE_OPTIONS=($(get_drive_list))

# Display drive selection dialog with proper formatting
if ! whiptail --title "Root-on-ZFS Drive Selection" \
    --backtitle "Device ID             Size      Type" \
    --separate-output \
    --checklist "Select drives for ZFS pool (use spacebar to select):" \
    $WHIP_HEIGHT $WHIP_WIDTH $((WHIP_HEIGHT - 8)) \
    "${DRIVE_OPTIONS[@]}" \
    2>"$TMP_DRIVES"; then
    echo "Selection cancelled."
    rm "$TMP_DRIVES" "$TMP_POOL"
    exit 1
fi

# Display pool type selection
if ! whiptail --title "ZFS Pool Configuration" \
    --radiolist "Select ZPool type:" \
    $WHIP_HEIGHT $WHIP_WIDTH 3 \
    "stripe" "Single/Multiple Drives (No Redundancy)" on \
    "mirror" "Mirror (RAID1)" off \
    "raidz" "RAIDZ (RAID5)" off \
    2>"$TMP_POOL"; then
    echo "Selection cancelled."
    rm "$TMP_DRIVES" "$TMP_POOL"
    exit 1
fi

# Get the selected drives and pool type
SELECTED_DRIVES=$(cat "$TMP_DRIVES")
POOL_TYPE=$(cat "$TMP_POOL")

# Clean up temporary files
rm "$TMP_DRIVES" "$TMP_POOL"

# Create config directory if it doesn't exist
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CONFIG_FILE="$SCRIPT_DIR/zfs_config.yaml"

# Generate YAML configuration with full paths
cat > "$CONFIG_FILE" << EOF
---
zfs_configuration:
  pool_type: $POOL_TYPE
  selected_drives:
$(for drive in $SELECTED_DRIVES; do
    echo "    - /dev/disk/by-id/$drive"
done)
EOF

# Show completion message
whiptail --title "Configuration Complete" \
    --msgbox "Configuration has been saved to: $CONFIG_FILE" \
    10 60

exit 0
