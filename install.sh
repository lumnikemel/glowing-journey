#!/bin/bash

# Configuration variables
CONFIG_FILE="install_config.conf"
LOG_FILE="install.log"

# Source configuration if it exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    # Default configuration values
    HOSTNAME="archzfs"
    USERNAME="user"
    TIMEZONE="UTC"
    LOCALE="en_US.UTF-8"
    KEYMAP="us"
    ZFS_POOL_NAME="zroot"
    SWAP_SIZE="32G"  # Adjust based on RAM size
    ROOT_SIZE="50G"
    HOME_SIZE="0"    # 0 means use remaining space
fi

# Color definitions for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Terminal dimensions
TERM_LINES=$(tput lines)
TERM_COLS=$(tput cols)
WHIPTAIL_HEIGHT=$((TERM_LINES - 8))
WHIPTAIL_WIDTH=$((TERM_COLS - 20))

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" >> "$LOG_FILE"
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} ${message}" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} ${message}" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} ${message}" ;;
    esac
}

# Error handling
set -e
trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR

error_handler() {
    local exit_code=$1
    local line_no=$2
    local last_command=$4
    whiptail --title "Error" --msgbox "An error occurred:\n\nLine: $line_no\nCommand: $last_command\nError code: $exit_code" \
        $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
    log ERROR "Error $exit_code occurred on line $line_no: $last_command"
    exit $exit_code
}

# Check if script is running with root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        whiptail --title "Error" --msgbox "This script must be run as root" $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
        log ERROR "This script must be run as root"
        exit 1
    fi
}

# Check if running from Arch Linux live media
check_arch_live() {
    if ! grep -q "Arch Linux" /etc/os-release; then
        whiptail --title "Error" --msgbox "This script must be run from Arch Linux live media" $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
        log ERROR "This script must be run from Arch Linux live media"
        exit 1
    fi
}

# Verify system is booted in UEFI mode
check_uefi() {
    if [ ! -d "/sys/firmware/efi/efivars" ]; then
        whiptail --title "Error" --msgbox "System not booted in UEFI mode" $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
        log ERROR "System not booted in UEFI mode"
        exit 1
    fi
}

# Function to detect available drives
detect_drives() {
    local nvme_drives=($(ls /dev/nvme[0-9]n1))
    if [ ${#nvme_drives[@]} -lt 2 ]; then
        whiptail --title "Error" --msgbox "Required minimum of 2 NVMe drives not found" $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
        log ERROR "Required minimum of 2 NVMe drives not found"
        exit 1
    fi
    echo "${nvme_drives[@]}"
}

# Initialize whiptail check
init_whiptail() {
    if ! command -v whiptail &> /dev/null; then
        pacman -Sy --noconfirm whiptail
    fi
}

# Drive selection interface with whiptail
select_drives() {
    local drives=($@)
    local options=()
    local i=1
    
    for drive in "${drives[@]}"; do
        local size=$(lsblk -dno SIZE "$drive")
        local model=$(lsblk -dno MODEL "$drive")
        options+=("$drive" "$model - $size" OFF)
    done
    
    local selected_drives=$(whiptail --title "Drive Selection" \
        --checklist "Select exactly 2 drives for installation:" \
        $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH $((${#drives[@]} + 2)) \
        "${options[@]}" \
        3>&1 1>&2 2>&3)
        
    if [ $? -ne 0 ]; then
        log ERROR "Drive selection cancelled"
        exit 1
    fi
    
    # Convert whiptail output to array
    selected_drives=$(echo "$selected_drives" | tr -d '"')
    local drive_array=($selected_drives)
    
    if [ ${#drive_array[@]} -ne 2 ]; then
        whiptail --title "Error" --msgbox "Please select exactly 2 drives" $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
        log ERROR "Invalid number of drives selected"
        exit 1
    fi
    
    echo "${drive_array[@]}"
}

# Configuration menu
show_config_menu() {
    local config_options=(
        1 "Hostname: $HOSTNAME"
        2 "Username: $USERNAME"
        3 "Timezone: $TIMEZONE"
        4 "Locale: $LOCALE"
        5 "Keymap: $KEYMAP"
        6 "ZFS Pool Name: $ZFS_POOL_NAME"
        7 "Save and Continue"
    )
    
    while true; do
        local choice=$(whiptail --title "Installation Configuration" \
            --menu "Configure installation parameters:" \
            $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH 7 \
            "${config_options[@]}" \
            3>&1 1>&2 2>&3)
            
        if [ $? -ne 0 ]; then
            log ERROR "Configuration cancelled"
            exit 1
        fi
        
        case $choice in
            1) HOSTNAME=$(whiptail --title "Hostname" --inputbox "Enter hostname:" \
                $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH "$HOSTNAME" 3>&1 1>&2 2>&3)
                ;;
            2) USERNAME=$(whiptail --title "Username" --inputbox "Enter username:" \
                $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH "$USERNAME" 3>&1 1>&2 2>&3)
                ;;
            3) TIMEZONE=$(whiptail --title "Timezone" --inputbox "Enter timezone:" \
                $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH "$TIMEZONE" 3>&1 1>&2 2>&3)
                ;;
            4) LOCALE=$(whiptail --title "Locale" --inputbox "Enter locale:" \
                $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH "$LOCALE" 3>&1 1>&2 2>&3)
                ;;
            5) KEYMAP=$(whiptail --title "Keymap" --inputbox "Enter keymap:" \
                $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH "$KEYMAP" 3>&1 1>&2 2>&3)
                ;;
            6) ZFS_POOL_NAME=$(whiptail --title "ZFS Pool Name" --inputbox "Enter ZFS pool name:" \
                $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH "$ZFS_POOL_NAME" 3>&1 1>&2 2>&3)
                ;;
            7) break
                ;;
        esac
        
        # Update menu options
        config_options=(
            1 "Hostname: $HOSTNAME"
            2 "Username: $USERNAME"
            3 "Timezone: $TIMEZONE"
            4 "Locale: $LOCALE"
            5 "Keymap: $KEYMAP"
            6 "ZFS Pool Name: $ZFS_POOL_NAME"
            7 "Save and Continue"
        )
    done
}

# Password input function
get_passwords() {
    # Get disk encryption password
    while true; do
        DISK_PASSWORD=$(whiptail --title "Disk Encryption" --passwordbox \
            "Enter disk encryption password:" $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH 3>&1 1>&2 2>&3)
        
        DISK_PASSWORD_CONFIRM=$(whiptail --title "Disk Encryption" --passwordbox \
            "Confirm disk encryption password:" $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH 3>&1 1>&2 2>&3)
        
        if [ "$DISK_PASSWORD" = "$DISK_PASSWORD_CONFIRM" ]; then
            break
        else
            whiptail --title "Error" --msgbox "Passwords do not match. Please try again." \
                $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
        fi
    done
    
    # Get user password
    while true; do
        USER_PASSWORD=$(whiptail --title "User Account" --passwordbox \
            "Enter password for user $USERNAME:" $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH 3>&1 1>&2 2>&3)
        
        USER_PASSWORD_CONFIRM=$(whiptail --title "User Account" --passwordbox \
            "Confirm password for user $USERNAME:" $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH 3>&1 1>&2 2>&3)
        
        if [ "$USER_PASSWORD" = "$USER_PASSWORD_CONFIRM" ]; then
            break
        else
            whiptail --title "Error" --msgbox "Passwords do not match. Please try again." \
                $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
        fi
    done
}

# Function to create and configure ZFS pool
setup_zfs_pool() {
    local drive1=$1
    local drive2=$2
    
    # Create partitions
    whiptail --title "Installation Progress" --infobox "Creating partitions..." $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
    for drive in "$drive1" "$drive2"; do
        sgdisk --zap-all "$drive"
        sgdisk -n1:1M:+1G -t1:EF00 "$drive" # EFI partition
        sgdisk -n2:0:0 -t2:BF00 "$drive"     # ZFS partition
    done
    
    # Setup encryption
    whiptail --title "Installation Progress" --infobox "Setting up disk encryption..." $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
    echo -n "$DISK_PASSWORD" | cryptsetup luksFormat "${drive1}-part2"
    echo -n "$DISK_PASSWORD" | cryptsetup luksFormat "${drive2}-part2"
    echo -n "$DISK_PASSWORD" | cryptsetup open "${drive1}-part2" cryptzfs1
    echo -n "$DISK_PASSWORD" | cryptsetup open "${drive2}-part2" cryptzfs2
    
    # Create ZFS pool
    whiptail --title "Installation Progress" --infobox "Creating ZFS pool..." $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
    zpool create -f -o ashift=12 \
                -O acltype=posixacl \
                -O relatime=on \
                -O xattr=sa \
                -O dnodesize=auto \
                -O normalization=formD \
                -O mountpoint=none \
                -O canmount=off \
                -O devices=off \
                -R /mnt \
                "$ZFS_POOL_NAME" mirror \
                /dev/mapper/cryptzfs1 \
                /dev/mapper/cryptzfs2
    
    # Create datasets
    whiptail --title "Installation Progress" --infobox "Creating ZFS datasets..." $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
    zfs create -o mountpoint=none "$ZFS_POOL_NAME/ROOT"
    zfs create -o mountpoint=/ "$ZFS_POOL_NAME/ROOT/default"
    zfs create -o mountpoint=/home "$ZFS_POOL_NAME/home"
    zfs create -o mountpoint=/var -o canmount=off "$ZFS_POOL_NAME/var"
    zfs create "$ZFS_POOL_NAME/var/cache"
    zfs create "$ZFS_POOL_NAME/var/log"
    zfs create "$ZFS_POOL_NAME/var/spool"
    zfs create "$ZFS_POOL_NAME/var/tmp"
    
    # Set ZFS properties
    whiptail --title "Installation Progress" --infobox "Setting ZFS properties..." $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
    zfs set compression=lz4 "$ZFS_POOL_NAME"
    zfs set atime=off "$ZFS_POOL_NAME"
}

[Previous functions remain the same...]

# Main installation function
main() {
    check_root
    check_arch_live
    check_uefi
    
    whiptail --title "Arch Linux Installation" --msgbox \
        "Welcome to the Arch Linux ZFS installer\n\nThis script will guide you through the installation process." \
        $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
    
    # Initialize whiptail
    init_whiptail
    
    # Show configuration menu
    show_config_menu
    
    # Detect and select drives
    local available_drives=($(detect_drives))
    local selected_drives=($(select_drives "${available_drives[@]}"))
    
    # Get passwords
    get_passwords
    
    # Confirm installation
    if ! whiptail --title "Confirm Installation" --yesno \
        "Warning: This will erase all data on the selected drives:\n\n${selected_drives[0]}\n${selected_drives[1]}\n\nDo you want to continue?" \
        $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH; then
        log INFO "Installation cancelled by user"
        exit 0
    fi
    
    # Perform installation with progress tracking
    setup_zfs_pool "${selected_drives[0]}" "${selected_drives[1]}"
    install_base_system
    configure_system
    
    whiptail --title "Installation Complete" --msgbox \
        "Installation completed successfully!\n\nPlease reboot your system." \
        $WHIPTAIL_HEIGHT $WHIPTAIL_WIDTH
    
    log INFO "Installation completed successfully!"
}

# Run main function
main "$@"
