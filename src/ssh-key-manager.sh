#!/bin/bash

# Log file
LOG_FILE="/var/log/ssh_key_manager.log"

# Excluded users
EXCLUDED_USERS=("root" "ubuntu" "nobody")

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Exiting..."
  exit 1
fi

# Function to log actions
log_action() {
  # Ensure the log file is writable
  if [ ! -w "$LOG_FILE" ]; then
    echo "Cannot write to log file $LOG_FILE. Check permissions. Exiting..."
    exit 1
  fi
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >>"$LOG_FILE"
}

# Function to check and install required packages
check_and_install_packages() {
  required_packages=("dialog" "curl" "sudo" "passwd" "adduser" "fzf")
  missing_packages=()

  for package in "${required_packages[@]}"; do
    if ! dpkg -l | grep -qw "$package"; then
      missing_packages+=("$package")
    fi
  done

  if [ ${#missing_packages[@]} -gt 0 ]; then
    echo "Installing missing packages: ${missing_packages[*]}"
    apt update && apt install -y "${missing_packages[@]}"
    if [ $? -ne 0 ]; then
      echo "Failed to install required packages. Exiting..."
      exit 1
    fi
  fi
}

# Generate exclusion regex for users
generate_exclusion_regex() {
  local exclusions=("$@")
  local regex=""
  for user in "${exclusions[@]}"; do
    regex+="|${user}"
  done
  regex=${regex:1} # Remove leading '|'
  echo "$regex"
}

# Function to add SSH key to user's authorized_keys
add_ssh_key() {
  # Generate exclusion regex
  exclusion_regex=$(generate_exclusion_regex "${EXCLUDED_USERS[@]}")

  # List all non-system users (UID >= 1000) excluding specified users
  user_list=$(awk -F: -v exclude="$exclusion_regex" '$3 >= 1000 && $1 !~ ("^(" exclude ")$") {print $1}' /etc/passwd)

  if [ -z "$user_list" ]; then
    dialog --msgbox "No valid users found." 8 50
    log_action "No valid users found to add SSH keys."
    return
  fi

  # Use fzf to select a user
  username=$(echo "$user_list" | fzf --prompt="Select a user to add SSH key: " --height=40% --reverse --border)
  if [ -z "$username" ]; then
    dialog --msgbox "No user selected. Operation canceled." 8 50
    log_action "No user selected. Operation canceled."
    return
  fi

  # Prompt for SSH key using dialog
  ssh_key=$(dialog --inputbox "Paste the SSH public key to add for '$username':" 15 80 2>&1 >/dev/tty)
  if [ $? -ne 0 ]; then
    dialog --msgbox "Operation canceled." 8 50
    log_action "SSH key addition canceled for user '$username'."
    return
  fi

  if [ -z "$ssh_key" ]; then
    dialog --msgbox "SSH key cannot be empty. Operation canceled." 8 50
    log_action "SSH key addition canceled for user '$username' due to empty input."
    return
  fi

  # Add the SSH key to the authorized_keys file
  user_home=$(eval echo "~$username")

  # Check if user home directory exists
  if [ ! -d "$user_home" ]; then
    dialog --msgbox "Home directory for user '$username' does not exist." 8 50
    log_action "Home directory does not exist for user '$username'."
    return
  fi

  ssh_dir="$user_home/.ssh"
  authorized_keys="$ssh_dir/authorized_keys"

  # Ensure .ssh directory exists and is writable
  if [ ! -d "$ssh_dir" ]; then
    mkdir -p "$ssh_dir"
    if [ $? -ne 0 ]; then
      dialog --msgbox "Failed to create .ssh directory for '$username'." 8 50
      log_action "Failed to create .ssh directory for user '$username'."
      return
    fi
    chmod 700 "$ssh_dir"
    chown "$username":"$username" "$ssh_dir"
  elif [ ! -w "$ssh_dir" ]; then
    dialog --msgbox ".ssh directory for '$username' is not writable." 8 50
    log_action ".ssh directory is not writable for user '$username'."
    return
  fi

  touch "$authorized_keys"
  chmod 600 "$authorized_keys"

  # Add the key and ensure no duplicates
  if grep -qF "$ssh_key" "$authorized_keys"; then
    dialog --msgbox "The SSH key already exists for '$username'." 8 50
    log_action "SSH key already exists for user '$username'."
  else
    echo "$ssh_key" >>"$authorized_keys"
    chown -R "$username":"$username" "$ssh_dir"
    dialog --msgbox "SSH key added successfully for '$username'." 8 50
    log_action "SSH key added for user '$username'."
  fi
}

# Ensure required packages are installed
check_and_install_packages

# Main menu
while true; do
  choice=$(dialog --clear --backtitle "SSH Key Manager" --title "Main Menu" \
    --nocancel --menu "Choose an action:" 15 60 3 \
    1 "Add SSH Key to User" \
    2 "Exit" \
    2>&1 >/dev/tty)

  clear
  case "$choice" in
    1) add_ssh_key ;;
    2) dialog --msgbox "Exiting SSH Key Manager." 8 50; clear; exit 0 ;;
    *) dialog --msgbox "Invalid option. Please try again." 8 50 ;;
  esac
done
