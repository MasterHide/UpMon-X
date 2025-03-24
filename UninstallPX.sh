#!/bin/bash

# Ensure the script is run as root
if [ "$(whoami)" != "root" ]; then
    echo -e "\e[31mError: This script must be run as the root user.\e[0m"
    exit 1
fi

# Stop and remove any services created by the installation
echo -e "\e[34mStopping and disabling upmon-x service...\e[0m"
sudo systemctl stop upmon-x || true
sudo systemctl disable upmon-x || true
sudo rm -f /etc/systemd/system/upmon-x.service

# Remove the project directory
echo -e "\e[34mRemoving project directory...\e[0m"
sudo rm -rf /home/ubuntu/upmon-x

# Remove any dependencies (if applicable)
# echo -e "\e[34mRemoving dependencies...\e[0m"
# sudo apt remove -y some-dependency || true

# Reload systemd to reflect changes
echo -e "\e[34mReloading systemd daemon...\e[0m"
sudo systemctl daemon-reload

# Final message
echo -e "\e[32mUninstallation complete! - UpMon-X\e[0m"
echo -e "\e[32mInstall Again If You Want UpMon-X - bash <(curl -s https://raw.githubusercontent.com/MasterHide/UpMon-X/main/InstallPX.sh)\e[0m"
