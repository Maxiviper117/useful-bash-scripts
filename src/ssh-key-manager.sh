#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Exiting..."
  exit 1
fi

# Log file
LOG_FILE="/var/log/ssh_key_manager.log"

# Ensure the log file exists and set correct permissions
if [ ! -f "$LOG_FILE" ]; then
  touch "$LOG_FILE"
  chmod 644 "$LOG_FILE"
  chown root:root "$LOG_FILE"
fi

# Ensure the log file is writable
if [ ! -w "$LOG_FILE" ]; then
  echo "Cannot write to log file $LOG_FILE. Check permissions. Exiting..."
  exit 1
fi

# Excluded users
EXCLUDED_USERS=("root" "ubuntu" "nobody")

# Function to log actions
log_action() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to handle SIGINT (Ctrl+c)
handle_sigint() {
  log_action "Script terminated by user using Ctrl+c."
  clear
  exit 1
}

# Trap SIGINT (Ctrl+c) and call handle_sigint
trap 'handle_sigint' SIGINT

# Function to check and install required packages
check_and_install_packages() {
  required_packages=("dialog" "curl" "sudo" "passwd" "adduser" "fzf" "openssh-server")
  missing_packages=()

  for package in "${required_packages[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
      missing_packages+=("$package")
    fi
  done

  if [ ${#missing_packages[@]} -gt 0 ]; then
    echo "Installing missing packages: ${missing_packages[*]}"
    apt update && apt install -y "${missing_packages[@]}"
    if [ $? -ne 0 ]; then
      echo "Failed to install required packages. Exiting..."
      log_action "Failed to install required packages: ${missing_packages[*]}"
      exit 1
    fi
    log_action "Installed missing packages: ${missing_packages[*]}"
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
    log_action "Created .ssh directory for user '$username'."
  elif [ ! -w "$ssh_dir" ]; then
    dialog --msgbox ".ssh directory for '$username' is not writable." 8 50
    log_action ".ssh directory is not writable for user '$username'."
    return
  fi

  touch "$authorized_keys"
  chmod 600 "$authorized_keys"

  # Add the SSH key and ensure no duplicates
  if grep -qF "$ssh_key" "$authorized_keys"; then
    dialog --msgbox "The SSH key already exists for '$username'." 8 50
    log_action "SSH key already exists for user '$username'."
  else
    echo "$ssh_key" >> "$authorized_keys"
    chown -R "$username":"$username" "$ssh_dir"
    dialog --msgbox "SSH key added successfully for '$username'." 8 50
    log_action "SSH key added for user '$username'."
  fi
}

# Function to manage /etc/ssh/sshd_config settings
manage_sshd_config() {
  config_file="/etc/ssh/sshd_config"

  # Ensure the config file is writable
  if [ ! -w "$config_file" ]; then
    dialog --msgbox "Cannot write to $config_file. Check permissions. Exiting..." 8 50
    log_action "Cannot write to $config_file. Check permissions."
    return
  fi

  # Backup the sshd_config before making changes
  cp "$config_file" "${config_file}.bak_$(date '+%Y%m%d%H%M%S')"
  if [ $? -eq 0 ]; then
    log_action "Backup of sshd_config created."
  else
    dialog --msgbox "Failed to create backup of sshd_config. Exiting..." 8 50
    log_action "Failed to create backup of sshd_config."
    return
  fi

  # Function to uncomment a configuration line if it's commented
  uncomment_config() {
    local config_option="$1"
    sed -i "s/^#\s*\(${config_option}\).*/\1/" "$config_file"
  }

  # Uncomment relevant configuration lines
  uncomment_config "PermitRootLogin"
  uncomment_config "PasswordAuthentication"

  while true; do
    config_choice=$(dialog --clear --backtitle "SSH Key Manager" --title "Manage sshd_config" \
      --nocancel --menu "Choose an action:\nPress Ctrl+c to exit immediately." 20 70 3 \
      1 "PermitRootLogin" \
      2 "PasswordAuthentication" \
      3 "Back to Main Menu" \
      2>&1 >/dev/tty)

    case "$config_choice" in
      1)
        # Get current value
        current_value=$(grep -E "^\s*PermitRootLogin" "$config_file" | tail -n 1 | awk '{print $2}')

        # Define options based on possible values
        # PermitRootLogin options: yes, no, prohibit-password
        new_value=$(dialog --radiolist "Current value: ${current_value:-not set}\nSelect new value for PermitRootLogin:\nPress Space to select, Enter to confirm." 15 60 4 \
          "yes" "Permit root login" $( [ "$current_value" = "yes" ] && echo "on" || echo "off") \
          "no" "Do not permit root login" $( [ "$current_value" = "no" ] && echo "on" || echo "off") \
          "prohibit-password" "Prohibit password login" $( [ "$current_value" = "prohibit-password" ] && echo "on" || echo "off") \
          2>&1 >/dev/tty)

        if [ $? -eq 0 ] && [ -n "$new_value" ]; then
          sed -i "s/^\s*PermitRootLogin.*/PermitRootLogin $new_value/" "$config_file"
          # Ensure the new setting exists
          if ! grep -q "PermitRootLogin $new_value" "$config_file"; then
            echo "PermitRootLogin $new_value" >> "$config_file"
          fi
          log_action "Updated PermitRootLogin to $new_value"
          dialog --msgbox "PermitRootLogin updated to '$new_value'.\n\nPlease restart the SSH service to apply changes." 10 60
        fi
        ;;
      2)
        # Get current value
        current_value=$(grep -E "^\s*PasswordAuthentication" "$config_file" | tail -n 1 | awk '{print $2}')

        # Check if current_value is 'yes' or 'no'
        if [[ "$current_value" != "yes" && "$current_value" != "no" ]]; then
          # Set default value to 'yes' if not set
          if [ -z "$current_value" ]; then
            default_value="yes"
            sed -i "/^\s*PasswordAuthentication/d" "$config_file"
            echo "PasswordAuthentication yes" >> "$config_file"
            current_value="yes"
            log_action "Set default PasswordAuthentication to 'yes' as it was not previously set."
          else
            # If the value is set to something else, set it to 'yes'
            default_value="yes"
            sed -i "s/^\s*PasswordAuthentication.*/PasswordAuthentication yes/" "$config_file"
            current_value="yes"
            log_action "Set PasswordAuthentication to 'yes' as it had an invalid value."
          fi
        else
          default_value="$current_value"
        fi

        # Define options: yes, no
        new_value=$(dialog --radiolist "Current value: $current_value\nSelect new value for PasswordAuthentication:\nPress Space to select, Enter to confirm." 12 60 2 \
          "yes" "Permit password authentication" $( [ "$current_value" = "yes" ] && echo "on" || echo "off") \
          "no" "Do not permit password authentication" $( [ "$current_value" = "no" ] && echo "on" || echo "off") \
          2>&1 >/dev/tty)

        if [ $? -eq 0 ] && [ -n "$new_value" ]; then
          sed -i "s/^\s*PasswordAuthentication.*/PasswordAuthentication $new_value/" "$config_file"
          # Ensure the new setting exists
          if ! grep -q "PasswordAuthentication $new_value" "$config_file"; then
            echo "PasswordAuthentication $new_value" >> "$config_file"
          fi
          log_action "Updated PasswordAuthentication to $new_value"
          dialog --msgbox "PasswordAuthentication updated to '$new_value'.\n\nPlease restart the SSH service to apply changes." 10 60
        fi
        ;;
      3) break ;;
      *) dialog --msgbox "Invalid option. Please try again." 8 50 ;;
    esac
  done
}

# Ensure required packages are installed
check_and_install_packages

# Main menu
while true; do
  choice=$(dialog --clear --backtitle "SSH Key Manager" --title "Main Menu" \
    --nocancel --menu "Choose an action:\nManage SSH keys and configurations easily.\n\nPress Ctrl+c to exit immediately." 20 70 3 \
    1 "Add SSH Key to User" \
    2 "Manage sshd_config Settings" \
    3 "Exit" \
    2>&1 >/dev/tty)

  clear
  case "$choice" in
    1) add_ssh_key ;;
    2) manage_sshd_config ;;
    3) 
      dialog --msgbox "Exiting SSH Key Manager." 8 50
      clear
      exit 0 
      ;;
    *) 
      dialog --msgbox "Invalid option. Please try again." 8 50 
      ;;
  esac
done
