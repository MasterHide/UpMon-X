#!/bin/bash

# Base directory for installation
BASE_DIR="/home/ubuntu"
PROJECT_DIR="$BASE_DIR/upmon-x"

# Ensure the script is run as root
if [ "$(whoami)" != "root" ]; then
    echo -e "\e[31mError: This script must be run as the root user.\e[0m"
    exit 1
fi

# Display the ASCII art banner
echo -e "\e[36m"
echo "db    db d8888b. .88b  d88.  .d88b.  d8b   db        db    db "
echo "88    88 88  \`8D 88'YbdP\`88 .8P  Y8. 888o  88        \`8b  d8' "
echo "88    88 88oodD' 88  88  88 88    88 88V8o 88         \`8bd8'  "
echo "88    88 88~~~   88  88  88 88    88 88 V8o88 C8888D  .dPYb.  "
echo "88b  d88 88      88  88  88 \`8b  d8' 88  V888        .8P  Y8. "
echo "~Y8888P' 88      YP  YP  YP  \`Y88P'  VP   V8P        YP    YP "
echo -e "\e[0m"

# Prompt for domain name (no IP support for Let's Encrypt)
read -p "Enter your domain name (e.g., example.com): " DOMAIN_OR_IP
if [ -z "$DOMAIN_OR_IP" ]; then
    echo -e "\e[31mError: Domain cannot be empty. Exiting.\e[0m"
    exit 1
fi

# Function to clean up old files
cleanup_old_files() {
    echo -e "\e[32mCleaning up old files...\e[0m"
    rm -rf /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    rm -rf /etc/apt/sources.list.d/caddy-stable.list
    rm -rf $PROJECT_DIR
    rm -f /etc/systemd/system/upmon-x.service  # Remove old systemd service file
}

# Function to install system dependencies
install_system_dependencies() {
    echo -e "\e[32mInstalling system dependencies...\e[0m"
    apt update
    apt install -y python3 python3-venv git curl socat ufw iputils-ping coreutils
}

# Function to install Caddy
install_caddy() {
    echo -e "\e[32mInstalling Caddy...\e[0m"
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install -y caddy
}

# Function to stop conflicting services (e.g., Nginx, Apache)
stop_conflicting_services() {
    echo -e "\e[32mStopping conflicting services...\e[0m"
    systemctl stop nginx || true
    systemctl disable nginx || true
    systemctl stop apache2 || true
    systemctl disable apache2 || true
}

# Function to clone the project repository
clone_project_repository() {
    echo -e "\e[32mDownloading project files...\e[0m"
    su - ubuntu -c "git clone https://github.com/MasterHide/UpMon-X.git $PROJECT_DIR"
}

# Function to set up Python environment and install Python dependencies
setup_python_environment() {
    echo -e "\e[32mSetting up Python environment...\e[0m"
    python3 -m venv $PROJECT_DIR/venv
    chown -R ubuntu:ubuntu $PROJECT_DIR  # Assign ownership to the 'ubuntu' user
    su - ubuntu -c "source $PROJECT_DIR/venv/bin/activate && pip install --upgrade pip && pip install flask requests gunicorn gunicorn[gevent]"
}

# Function to configure Caddy
configure_caddy() {
    echo -e "\e[32mConfiguring Caddy...\e[0m"
    cat <<EOF | sudo tee /etc/caddy/Caddyfile > /dev/null
$DOMAIN_OR_IP {
    encode gzip
    reverse_proxy 127.0.0.1:8000
}
EOF

    echo -e "\e[32mRestarting Caddy...\e[0m"
    sudo systemctl restart caddy
}

# Function to free port 8000 if it's in use
free_port_8000() {
    echo -e "\e[32mFreeing port 8000...\e[0m"
    lsof -i :8000 | awk 'NR>1 {print $2}' | xargs sudo kill -9 || true
}

# Function to create systemd service file for Gunicorn
create_gunicorn_service() {
    echo -e "\e[32mCreating systemd service file for UpMon-X...\e[0m"

    # Remove old service file if it exists
    if [ -f "/etc/systemd/system/upmon-x.service" ]; then
        echo -e "\e[33mRemoving old systemd service file...\e[0m"
        rm -f /etc/systemd/system/upmon-x.service
    fi

    # Create new service file
    sudo tee /etc/systemd/system/upmon-x.service > /dev/null <<EOF
[Unit]
Description=Gunicorn instance for UpMon-X
After=network.target

[Service]
User=ubuntu
Group=www-data
WorkingDirectory=$PROJECT_DIR
ExecStartPre=/bin/sleep 10
ExecStart=/bin/bash -c "exec $PROJECT_DIR/venv/bin/gunicorn --chdir $PROJECT_DIR -w 4 -b 0.0.0.0:8000 --worker-class gevent --timeout 120 --log-level debug upx:app"
Restart=always
Environment="PATH=$PROJECT_DIR/venv/bin"

[Install]
WantedBy=multi-user.target
EOF

    echo -e "\e[32mReloading systemd and starting UpMon-X service...\e[0m"
    sudo systemctl daemon-reload
    sudo systemctl enable upmon-x
    sudo systemctl start upmon-x
}

# Function to verify Gunicorn is running
verify_gunicorn() {
    sleep 5
    if ! systemctl is-active --quiet upmon-x; then
        echo -e "\e[31mGunicorn failed to start. Exiting.\e[0m"
        exit 1
    fi
}

# Main script execution
echo -e "\e[32mStarting setup process...\e[0m"

# Clean up old files
cleanup_old_files

# Install system dependencies
install_system_dependencies

# Install Caddy
install_caddy

# Stop conflicting services
stop_conflicting_services

# Clone the project repository
clone_project_repository

# Set up Python environment and install Python dependencies
setup_python_environment

# Configure Caddy
configure_caddy

# Free port 8000 if it's in use
free_port_8000

# Create systemd service file for Gunicorn
create_gunicorn_service

# Verify Gunicorn is running
verify_gunicorn

# Ensure servers.json exists with proper permissions
echo -e "\e[32mEnsuring servers.json exists...\e[0m"
sudo touch /home/ubuntu/upmon-x/servers.json
sudo chown ubuntu:ubuntu /home/ubuntu/upmon-x/servers.json
sudo chmod 600 /home/ubuntu/upmon-x/servers.json

# Ensure templates directory exists
echo -e "\e[32mEnsuring templates directory exists...\e[0m"
mkdir -p /home/ubuntu/upmon-x/templates
chown -R ubuntu:ubuntu /home/ubuntu/upmon-x/templates

# Ensure static directory exists
echo -e "\e[32mEnsuring static directory exists...\e[0m"
mkdir -p /home/ubuntu/upmon-x/static
chown -R ubuntu:ubuntu /home/ubuntu/upmon-x/static

echo -e "\e[32mSetup complete!\e[0m"
echo -e "\e[32mAccess the Web at Admin Url - https://$DOMAIN_OR_IP/adminpanel\e[0m"
echo -e "\e[32mAccess the Web at User - https://$DOMAIN_OR_IP\e[0m"
