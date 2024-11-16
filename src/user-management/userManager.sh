#!/bin/bash

# This script provides a simple user management tool for Linux systems.
# It allows you to create, delete, and list users with an interactive menu.
# Users can be granted sudo access during creation.

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to create a user
create_user() {
  read -p "${BLUE}Enter the username:${NC} " username

  # Check if the user already exists
  if id -u "$username" >/dev/null 2>&1; then
    echo -e "${RED}User '$username' already exists.${NC}"
    return
  fi

  # Prompt for password
  echo -e "${BLUE}Enter a password for '$username':${NC}"
  read -s password
  echo -e "${BLUE}Confirm the password for '$username':${NC}"
  read -s confirm_password

  if [ "$password" != "$confirm_password" ]; then
    echo -e "${RED}Passwords do not match. Try again.${NC}"
    return
  fi

  # Create user with home directory
  sudo adduser --disabled-password --gecos "" "$username"
  echo "$username:$password" | sudo chpasswd

  # Ask about sudo access
  read -p "${BLUE}Grant sudo access to '$username'? [y/N]:${NC} " grant_sudo
  if [[ "$grant_sudo" =~ ^[Yy]$ ]]; then
    sudo usermod -aG sudo "$username"
    echo -e "${GREEN}Sudo access granted to '$username'.${NC}"
  fi

  # Ensure home directory exists and has correct permissions
  sudo mkdir -p "/home/$username"
  sudo chown "$username:$username" "/home/$username"
  sudo chmod 750 "/home/$username"

  echo -e "${GREEN}User '$username' created successfully.${NC}"
}

# Function to delete a user
delete_user() {
  read -p "${BLUE}Enter the username to delete:${NC} " username

  # Check if the user exists
  if ! id -u "$username" >/dev/null 2>&1; then
    echo -e "${RED}User '$username' does not exist.${NC}"
    return
  fi

  # Confirm and delete the user
  read -p "${YELLOW}Are you sure you want to delete '$username'? [y/N]:${NC} " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    sudo deluser "$username"
    echo -e "${GREEN}User '$username' deleted successfully.${NC}"
  else
    echo -e "${YELLOW}Operation canceled.${NC}"
  fi
}

# Function to list all users
list_users() {
  echo -e "${BLUE}List of users:${NC}"
  cut -d: -f1 /etc/passwd
}

# Main menu
while true; do
  echo
  echo -e "${YELLOW}User Manager${NC}"
  echo -e "${BLUE}A simple tool to manage users on a Linux system.${NC}\n"
  echo -e "${BLUE}1. Create a User${NC} - Create a new user with optional sudo access"
  echo -e "${BLUE}2. Delete a User${NC} - Remove an existing user from the system"
  echo -e "${BLUE}3. List All Users${NC} - Display a list of all system users"
  echo -e "${BLUE}4. Exit${NC} - Exit the User Manager"
  read -p "${GREEN}Choose an option [1-4]:${NC} " choice

  case "$choice" in
    1) create_user ;;
    2) delete_user ;;
    3) list_users ;;
    4) echo -e "${YELLOW}Exiting...${NC}"; exit 0 ;;
    *) echo -e "${RED}Invalid option. Please try again.${NC}" ;;
  esac
done
