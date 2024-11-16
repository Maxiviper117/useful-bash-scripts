#!/bin/bash

# Log file
LOG_FILE="/var/log/user_manager.log"

# Users to exclude from listings and searches
EXCLUDED_USERS=("root" "ubuntu" "nobody")  # Add more usernames here as needed

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Exiting..."
  exit 1
fi

# Function to log actions
log_action() {
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

# Function to generate awk exclusion pattern for users
generate_user_exclusion_regex() {
  local exclusions=("$@")
  local regex=""
  for user in "${exclusions[@]}"; do
    regex+="|${user}"
  done
  regex=${regex:1}  # Remove leading '|'
  echo "$regex"
}

# Check and install required packages
check_and_install_packages

# Function to handle terminal resize
handle_resize() {
  TERM_WIDTH=$(tput cols)
  TERM_HEIGHT=$(tput lines)
}

# Trap the SIGWINCH signal to handle window resize
trap handle_resize SIGWINCH

# Initialize terminal size
handle_resize

# Function to create a user
create_user() {
  while true; do
    username=$(dialog --inputbox "Enter the username:" $((TERM_HEIGHT / 2)) $((TERM_WIDTH / 2)) 2>&1 >/dev/tty)
    username=$(echo "$username" | tr '[:upper:]' '[:lower:]')

    # Check if Cancel was pressed
    if [ $? -ne 0 ]; then
      break
    fi

    if [ -z "$username" ]; then
      dialog --msgbox "Username cannot be empty." 8 50
      continue
    fi

    if id -u "$username" >/dev/null 2>&1; then
      dialog --msgbox "User '$username' already exists." 8 50
      continue
    fi

    password=$(dialog --passwordbox "Enter password for '$username':" 10 50 2>&1 >/dev/tty)
    if [ $? -ne 0 ]; then
      break
    fi

    confirm_password=$(dialog --passwordbox "Confirm password for '$username':" 10 50 2>&1 >/dev/tty)
    if [ $? -ne 0 ]; then
      break
    fi

    if [ "$password" != "$confirm_password" ]; then
      dialog --msgbox "Passwords do not match." 8 50
      continue
    fi

    # Create the user with default shell /bin/bash
    if ! adduser --disabled-password --gecos "" --shell /bin/bash "$username"; then
      dialog --msgbox "Failed to create user '$username'. Please check system logs." 8 50
      log_action "Failed to create user '$username'."
      break
    fi

    # Set the user's password
    if ! echo "$username:$password" | chpasswd; then
      dialog --msgbox "Failed to set password for user '$username'. Please check system logs." 8 50
      log_action "Failed to set password for user '$username'."
      break
    fi

    # Set proper permissions for the home directory
    home_dir=$(eval echo "~$username")
    chmod 755 "$home_dir"
    log_action "Set permissions for home directory of '$username'."

    dialog --yesno "Grant sudo access to '$username'?" 8 50
    if [ $? -eq 0 ]; then
      if ! usermod -aG sudo "$username"; then
        dialog --msgbox "Failed to grant sudo access to '$username'. Please check system logs." 8 50
        log_action "Failed to grant sudo access to '$username'."
        break
      fi
      dialog --msgbox "Sudo access granted to '$username'." 8 50
      log_action "Granted sudo access to '$username'."
    fi

    dialog --msgbox "User '$username' created successfully." 8 50
    log_action "User '$username' created successfully."
    break
  done
}

# Function to delete a user
delete_user() {
  # Select username using fzf
  exclusion_regex=$(generate_user_exclusion_regex "${EXCLUDED_USERS[@]}")
  user_list=$(awk -F: -v exclude="$exclusion_regex" '$3 >= 1000 && $1 !~ ("^(" exclude ")$") {print $1}' /etc/passwd)
  
  username=$(echo "$user_list" | fzf --prompt="Select a user to delete (Press Ctrl+C to cancel): " --height=40% --reverse --border)
  
  if [ -z "$username" ]; then
    dialog --msgbox "No user selected. Operation canceled." 8 50
    return
  fi

  if [ "$username" == "root" ]; then
    dialog --msgbox "You cannot delete the root user." 8 50
    return
  fi

  dialog --yesno "Are you sure you want to delete '$username'?" 8 50
  if [ $? -eq 0 ]; then
    if ! deluser "$username"; then
      dialog --msgbox "Failed to delete user '$username'. Please check system logs." 8 50
      log_action "Failed to delete user '$username'."
    else
      dialog --msgbox "User '$username' deleted successfully." 8 50
      log_action "User '$username' deleted successfully."
    fi
  fi
}

# Function to list all non-system users excluding specific users
list_users() {
  # Generate exclusion regex for users
  exclusion_regex=$(generate_user_exclusion_regex "${EXCLUDED_USERS[@]}")

  # Get list of non-system users excluding specified users
  user_list=$(awk -F: -v exclude="$exclusion_regex" '
    $3 >= 1000 && $1 !~ ("^(" exclude ")$") {print $1}
  ' /etc/passwd)

  if [ -z "$user_list" ]; then
    dialog --msgbox "No non-system users found." 8 50
    return
  fi

  # Prepare detailed information
  detailed_list=""
  for username in $user_list; do
    uid=$(id -u "$username")
    home_dir=$(eval echo "~$username")
    groups=$(id -Gn "$username")
    detailed_list+="Username: $username\nUID: $uid\nHome Directory: $home_dir\nGroups: $groups\n\n"
  done

  # Display in dialog
  dialog --msgbox "List of non-system users:\n\n$detailed_list" 25 80
}

# Function to search for a user using fzf, excluding specific users
search_user() {
  # Generate exclusion regex for users
  exclusion_regex=$(generate_user_exclusion_regex "${EXCLUDED_USERS[@]}")

  # Get a list of all non-system users excluding specified users
  user_list=$(awk -F: -v exclude="$exclusion_regex" '$3 >= 1000 && $1 !~ ("^(" exclude ")$") {print $1}' /etc/passwd)
  
  if [ -z "$user_list" ]; then
    dialog --msgbox "No users found to search." 8 50
    return
  fi

  # Use fzf to select a user
  username=$(echo "$user_list" | fzf --prompt="Search for a user (Press Ctrl+C to cancel): " --height=40% --reverse --border)

  # If no user is selected (ESC or empty selection)
  if [ -z "$username" ]; then
    dialog --msgbox "No user selected." 8 50
    return
  fi

  # Display details about the selected user
  if id "$username" >/dev/null 2>&1; then
    details=$(id "$username")
    home_dir=$(eval echo "~$username")
    disk_usage=$(du -sh "$home_dir" 2>/dev/null | awk '{print $1}')
    dialog --msgbox "Details for user '$username':\n\n$details\nHome Directory: $home_dir\nDisk Usage: ${disk_usage:-N/A}" 15 80
  else
    dialog --msgbox "User '$username' not found." 8 50
  fi
}

# Function to manage groups
manage_groups() {
  while true; do
    choice=$(dialog --menu "Group Management Options:" 15 60 7 \
      1 "Create a Group" \
      2 "Delete a Group" \
      3 "Add User to a Group" \
      4 "Remove User from a Group" \
      5 "List Groups and Details" \
      6 "Back to Main Menu" \
      7 "Cancel" \
      2>&1 >/dev/tty)

    case "$choice" in
      1)
        group_name=$(dialog --inputbox "Enter the group name to create:" 10 50 2>&1 >/dev/tty)
        if [ $? -ne 0 ] || [ -z "$group_name" ]; then
          dialog --msgbox "Group creation canceled or invalid input." 8 50
          continue
        fi
        if groupadd "$group_name"; then
          dialog --msgbox "Group '$group_name' created successfully." 8 50
          log_action "Group '$group_name' created."
        else
          dialog --msgbox "Failed to create group '$group_name'." 8 50
          log_action "Failed to create group '$group_name'."
        fi
        ;;
      2)
        # Delete a Group using fzf for selection
        group_list=$(getent group | awk -F: '$3 >= 1000 && $1 != "nogroup" && $1 != "ubuntu" {print $1}')
        group_name=$(echo "$group_list" | fzf --prompt="Select a group to delete (Press Ctrl+C to cancel): " --height=40% --reverse --border)
        
        if [ -z "$group_name" ]; then
          dialog --msgbox "No group selected. Operation canceled." 8 50
          continue
        fi
        
        if groupdel "$group_name"; then
          dialog --msgbox "Group '$group_name' deleted successfully." 8 50
          log_action "Group '$group_name' deleted."
        else
          dialog --msgbox "Failed to delete group '$group_name'." 8 50
          log_action "Failed to delete group '$group_name'."
        fi
        ;;
      3)
        # Add User to a Group with fzf for user selection
        user_list=$(awk -F: '$3 >= 1000 && $1 !~ ("^(root|ubuntu)$") {print $1}' /etc/passwd)
        username=$(echo "$user_list" | fzf --prompt="Select a user to add to a group (Press Ctrl+C to cancel): " --height=40% --reverse --border)
        if [ -z "$username" ]; then
          dialog --msgbox "No user selected. Operation canceled." 8 50
          continue
        fi

        # Check if user exists
        if ! id -u "$username" >/dev/null 2>&1; then
          dialog --msgbox "User '$username' does not exist." 8 50
          continue
        fi

        # Generate exclusion regex for groups if needed (optional)
        # Currently, we're listing all non-system groups (GID >=1000)
        group_list=$(awk -F: '$3 >= 1000 && $1 != "nogroup" && $1 != "ubuntu" {print $1}' /etc/group)

        if [ -z "$group_list" ]; then
          dialog --msgbox "No non-system groups available to add." 8 50
          continue
        fi

        # Use fzf to select a group
        group_name=$(echo "$group_list" | fzf --prompt="Select a group to add '$username' to (Press Ctrl+C to cancel): " --height=40% --reverse --border)

        # If no group is selected
        if [ -z "$group_name" ]; then
          dialog --msgbox "No group selected. Operation canceled." 8 50
          continue
        fi

        # Add user to the selected group
        if usermod -aG "$group_name" "$username"; then
          dialog --msgbox "User '$username' added to group '$group_name'." 8 50
          log_action "User '$username' added to group '$group_name'."
        else
          dialog --msgbox "Failed to add user '$username' to group '$group_name'." 8 50
          log_action "Failed to add user '$username' to group '$group_name'."
        fi
        ;;
      4)
        # Remove User from a Group
        # Use fzf to select a user
        user_list=$(awk -F: '$3 >= 1000 && $1 !~ ("^(root|ubuntu|nobody)$") {print $1}' /etc/passwd)
        username=$(echo "$user_list" | fzf --prompt="Select a user to remove from a group (Press Ctrl+C to cancel): " --height=40% --reverse --border)
        if [ -z "$username" ]; then
          dialog --msgbox "No user selected. Operation canceled." 8 50
          continue
        fi

        # Use fzf to select a group
        group_list=$(getent group | awk -F: '$3 >= 1000 && $1 != "nogroup" && $1 != "ubuntu" {print $1}')
        group_name=$(echo "$group_list" | fzf --prompt="Select a group to remove '$username' from (Press Ctrl+C to cancel): " --height=40% --reverse --border)
        if [ -z "$group_name" ]; then
          dialog --msgbox "No group selected. Operation canceled." 8 50
          continue
        fi

        # Remove user from the selected group
        if gpasswd -d "$username" "$group_name"; then
          dialog --msgbox "User '$username' removed from group '$group_name'." 8 50
          log_action "User '$username' removed from group '$group_name'."
        else
          dialog --msgbox "Failed to remove user '$username' from group '$group_name'." 8 50
          log_action "Failed to remove user '$username' from group '$group_name'."
        fi
        ;;
      5)
        # List Groups and Details excluding system groups
        group_list=$(awk -F: '$3 >= 1000 && $1 != "nogroup" && $1 != "ubuntu" {print "Group Name: "$1"\nGroup ID: "$3"\nMembers: "$4"\n"}' /etc/group | sed 's/$/\\n/')
        if [ -z "$group_list" ]; then
          dialog --msgbox "No non-system groups found." 8 50
        else
          dialog --msgbox "Group Details:\n\n$group_list" 25 80
        fi
        ;;
      6)
        break  # Return to Main Menu
        ;;
      7)
        dialog --msgbox "Group Management canceled." 8 50
        break
        ;;
      *)
        dialog --msgbox "Invalid option. Please try again." 8 50
        ;;
    esac
  done
}

# Main menu
while true; do
  choice=$(dialog --clear --backtitle "User Manager" --title "Main Menu" \
    --menu "Manage system users and groups with ease.\nChoose an action:" 20 60 6 \
    1 "Create a User" \
    2 "Delete a User" \
    3 "List All Users" \
    4 "Search for a User" \
    5 "Manage Groups" \
    6 "Exit" \
    2>&1 >/dev/tty)

  clear
  case "$choice" in
    1) create_user ;;
    2) delete_user ;;
    3) list_users ;;
    4) search_user ;;
    5) manage_groups ;;
    6) dialog --msgbox "Exiting User Manager." 8 50; clear; exit 0 ;;
    *) dialog --msgbox "Invalid option. Please try again." 8 50 ;;
  esac
done
