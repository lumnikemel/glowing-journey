#!/bin/bash

# Function to get all available drives
get_drives() {
    lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop" | grep -v "sr0"
}

# Function to format drives for whiptail checklist
format_drives_list() {
    local count=1
    while read -r line; do
        local name=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local model=$(echo "$line" | cut -d' ' -f3-)
        echo "$name \"$size - $model\" off"
        ((count++))
    done
}

# Create temporary files for storing selections
TMP_DRIVES=$(mktemp)
TMP_POOL=$(mktemp)

# Get terminal dimensions
TERM_HEIGHT=$(tput lines)
TERM_WIDTH=$(tput cols)

# Calculate whiptail window dimensions
WHIP_HEIGHT=$((TERM_HEIGHT - 8))
WHIP_WIDTH=$((TERM_WIDTH - 20))

# Display drive selection dialog
get_drives | format_drives_list | xargs whiptail --title "Root-on-ZFS Drive Selection" \
    --checklist "Select drives for ZFS pool (use spacebar to select):" \
    $WHIP_HEIGHT $WHIP_WIDTH $((WHIP_HEIGHT - 8)) \
    3>&1 1>&2 2>&3 > "$TMP_DRIVES"

# Check if user cancelled
if [ $? -ne 0 ]; then
    echo "Selection cancelled."
    rm "$TMP_DRIVES" "$TMP_POOL"
    exit 1
fi

# Display pool type selection
whiptail --title "ZFS Pool Configuration" \
    --radiolist "Select ZPool type:" \
    $WHIP_HEIGHT $WHIP_WIDTH 3 \
    "stripe" "Single/Multiple Drives (No Redundancy)" on \
    "mirror" "Mirror (RAID1)" off \
    "raidz" "RAIDZ (RAID5)" off \
    3>&1 1>&2 2>&3 > "$TMP_POOL"

# Check if user cancelled
if [ $? -ne 0 ]; then
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

# Generate YAML configuration
cat > "$CONFIG_FILE" << EOF
---
zfs_configuration:
  pool_type: $POOL_TYPE
  selected_drives:
$(echo "$SELECTED_DRIVES" | tr ' ' '\n' | sed 's/^/    - /')
EOF

# Show completion message
whiptail --title "Configuration Complete" \
    --msgbox "Configuration has been saved to: $CONFIG_FILE" \
    10 60

exit 0
