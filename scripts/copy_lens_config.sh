#!/bin/bash
# Script to copy the Lens kubeconfig to a remote machine

# Default destination is Desktop
DEST="~/Desktop/yekvitka-lens-config.yaml"

# Check if an argument was provided
if [ "$1" != "" ]; then
  DEST="$1"
fi

# Display info
echo "This script will copy the Lens cluster config to a remote machine"
echo "Usage: $0 [destination_path]"
echo ""

# Ask for remote details
read -p "Enter remote username: " USERNAME
read -p "Enter remote hostname or IP: " HOSTNAME
echo "Will copy to ${USERNAME}@${HOSTNAME}:${DEST}"
echo ""

# Confirm before proceeding
read -p "Continue (y/n)? " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "Operation cancelled"
  exit 1
fi

# Execute the copy
echo "Copying configuration file..."
scp /home/pimaster/pi-cluster/configs/working-lens-config.yaml ${USERNAME}@${HOSTNAME}:${DEST}

if [ $? -eq 0 ]; then
  echo ""
  echo "Success! The kubeconfig file has been copied to ${USERNAME}@${HOSTNAME}:${DEST}"
  echo "You can now import this file into Lens following the instructions in lens-import-guide.md"
else
  echo ""
  echo "Error: Failed to copy the configuration file"
  echo "Please check your network connection and the remote machine accessibility"
fi
