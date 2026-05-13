#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to check if the script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root."
        exit 1
    fi
}

# Function to get a valid SSH port from the user
get_ssh_port() {
    while true; do
        read -rp "Enter new SSH port (1024-65535): " NEW_PORT
        if [[ "$NEW_PORT" =~ ^[0-9]+$ ]] && [ "$NEW_PORT" -ge 1024 ] && [ "$NEW_PORT" -le 65535 ]; then
            break
        else
            echo "Invalid port. Please enter a number between 1024 and 65535."
        fi
    done
}

# Function to change the SSH port
change_ssh_port() {
    SSH_CONFIG="/etc/ssh/sshd_config"
    
    # Backup current config
    cp "$SSH_CONFIG" "${SSH_CONFIG}.bak"
    echo "Backup of sshd_config saved as sshd_config.bak"
    
    # Replace or add the Port directive
    if grep -q "^Port" "$SSH_CONFIG"; then
        sed -i "s/^Port.*/Port $NEW_PORT/" "$SSH_CONFIG"
    else
        echo "Port $NEW_PORT" >> "$SSH_CONFIG"
    fi
    
    # Restart SSH service
    systemctl restart ssh
    echo "SSH port changed to $NEW_PORT and service restarted."
}

# Function to install UFW and configure firewall
setup_firewall() {
    apt-get update
    apt-get install -y ufw

    # Reset UFW to default state
    ufw --force reset

    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing

    # Allow new SSH port
    ufw allow "$NEW_PORT"/tcp

    # Allow common services (optional)
    ufw allow 80/tcp   # HTTP
    ufw allow 443/tcp  # HTTPS

    # Enable UFW
    ufw --force enable
    echo "Firewall configured and enabled."
}

# Function to apply additional security hardening
apply_security_hardening() {
    # Disable root login via SSH
    sed -i "s/^PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
    systemctl restart ssh

    # Limit SSH login attempts
    apt-get install -y fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban

    echo "Security hardening applied: root login disabled, fail2ban enabled."
}

# Function to create a new user
create_new_user() {
    read -rp "Enter new username: " NEW_USER
    # Generate a strong random password using openssl
    SUGGESTED_PASSWORD=$(openssl rand -base64 16)
    echo "Suggested secure password for $NEW_USER: $SUGGESTED_PASSWORD"
    
    # Ask if user wants to use the suggested password or custom
    read -rp "Use suggested password? (y/n): " USE_SUGGESTED
    if [[ "$USE_SUGGESTED" =~ ^[Yy]$ ]]; then
        PASSWORD="$SUGGESTED_PASSWORD"
    else
        read -rsp "Enter password for $NEW_USER: " PASSWORD
        echo
    fi
    
    # Create the user with password and add to sudo group
    useradd -m -s /bin/bash "$NEW_USER"
    echo "$NEW_USER:$PASSWORD" | chpasswd
    usermod -aG sudo "$NEW_USER"
    echo "User $NEW_USER created and added to sudo group."
}

# Main script execution
check_root
get_ssh_port
change_ssh_port
setup_firewall
apply_security_hardening
create_new_user

echo "All tasks completed successfully! New SSH port: $NEW_PORT"
