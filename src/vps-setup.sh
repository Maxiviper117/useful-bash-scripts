#!/bin/bash

# Global Variables
DEV=false

# Spinner for visual feedback
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    echo -n " "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    echo "    "
}

# Main menu
main_menu() {
    while true; do
        choice=$(dialog --clear --backtitle "Laravel VPS Setup" \
            --title "Main Menu" \
            --menu "Choose an option:" 15 50 8 \
            1 "Update Packages" \
            2 "Add New User" \
            3 "Add Deploy User" \
            4 "Setup Nginx" \
            5 "Setup PHP and Composer" \
            6 "Setup Firewall" \
            7 "List Users" \
            8 "Exit" \
            2>&1 >/dev/tty)

        clear

        case $choice in
            1) update_packages ;;
            2) add_user ;;
            3) add_deploy_user ;;
            4) setup_nginx ;;
            5) setup_php ;;
            6) setup_firewall ;;
            7) list_users ;;
            8) echo "Goodbye!"; exit ;;
        esac
    done
}

# Update system packages
update_packages() {
    echo "Updating packages..."
    if [ "$DEV" = false ]; then
        sudo apt update && sudo apt upgrade -y &
        spinner
    fi
    echo "Packages updated successfully."
}

# Add a new user
add_user() {
    username=$(dialog --inputbox "Enter the username for the new user:" 8 40 2>&1 >/dev/tty)
    password=$(dialog --passwordbox "Enter the password for the new user:" 8 40 2>&1 >/dev/tty)
    confirm_password=$(dialog --passwordbox "Confirm the password:" 8 40 2>&1 >/dev/tty)

    if [ "$password" != "$confirm_password" ]; then
        dialog --msgbox "Passwords do not match. Please try again." 6 40
        return
    fi

    echo "Adding user $username..."
    if [ "$DEV" = false ]; then
        sudo adduser --disabled-password --gecos "" "$username" &
        spinner
        echo "$username:$password" | sudo chpasswd &
        spinner
        sudo usermod -aG sudo "$username" &
        spinner
    fi
    dialog --msgbox "User $username added successfully." 6 40
}

# Add a deploy user
add_deploy_user() {
    username=$(dialog --inputbox "Enter the deploy username:" 8 40 2>&1 >/dev/tty)
    deploy_username="deploy-$username"

    echo "Adding deploy user $deploy_username..."
    if [ "$DEV" = false ]; then
        sudo adduser "$deploy_username" &
        spinner
        sudo usermod -aG sudo "$deploy_username" &
        spinner
    fi
    dialog --msgbox "Deploy user $deploy_username added successfully." 6 40
}

# Setup Nginx
setup_nginx() {
    echo "Setting up Nginx..."
    if [ "$DEV" = false ]; then
        sudo apt update &
        spinner
        sudo apt install -y nginx &
        spinner
        sudo ufw allow 'Nginx Full' &
        spinner
    fi
    dialog --msgbox "Nginx installed and configured successfully." 6 40
}

# Setup PHP and Composer
setup_php() {
    php_choice=$(dialog --menu "PHP Setup Options" 12 50 2 \
        1 "Install PHP and Composer" \
        2 "Install PHP Extensions for Databases" \
        2>&1 >/dev/tty)

    case $php_choice in
        1) install_php_composer ;;
        2) setup_php_extensions_for_databases ;;
    esac
}

install_php_composer() {
    echo "Installing PHP and Composer..."
    if [ "$DEV" = false ]; then
        sudo apt install -y php php-cli php-fpm php-json php-common php-zip php-gd php-mbstring php-curl php-xml php-bcmath wget unzip composer &
        spinner
    fi
    dialog --msgbox "PHP and Composer installed successfully." 6 40
}

setup_php_extensions_for_databases() {
    extensions=$(dialog --checklist "Select PHP extensions to install:" 15 50 6 \
        1 "PHP MySQL Extension" on \
        2 "PHP PostgreSQL Extension" off \
        3 "PHP SQLite Extension" off \
        2>&1 >/dev/tty)

    echo "Installing PHP extensions: $extensions..."
    if [ "$DEV" = false ]; then
        sudo apt install -y $extensions &
        spinner
    fi
    dialog --msgbox "PHP extensions installed successfully." 6 40
}

# Setup Firewall
setup_firewall() {
    echo "Configuring firewall..."
    if [ "$DEV" = false ]; then
        sudo ufw allow OpenSSH &
        spinner
        sudo ufw allow 'Nginx Full' &
        spinner
        echo "y" | sudo ufw enable &
        spinner
    fi
    dialog --msgbox "Firewall configured successfully." 6 40
}

# List current users
list_users() {
    echo "Listing users and their groups..."
    if [ "$DEV" = false ]; then
        cut -d: -f1 /etc/passwd | while read user; do
            groups=$(groups $user)
            echo "$user: $groups"
        done > /tmp/userlist.txt
    fi
    dialog --textbox /tmp/userlist.txt 20 60
    rm /tmp/userlist.txt
}

# Start the script
main_menu
