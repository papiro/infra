#!/usr/bin/env bash
# SSHs to an EC2 instance
# Usage:
# ./connect.sh user@ip-address ssh-key-path

set -euo pipefail

print_usage() {
  echo "Usage: $0 <user@ip-address> <ssh-key-path>"
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

USER_AND_IP_ADDRESS=${1-}
SSH_KEY_PATH=${2-}

if [ -z "${USER_AND_IP_ADDRESS}" ]; then
  echo "Error: User and IP address are required" >&2
  print_usage
fi

if [ -z "${SSH_KEY_PATH}" ]; then
  echo "Error: SSH key path is required" >&2
  print_usage
fi

USER_AND_IP_ADDRESS=(${USER_AND_IP_ADDRESS//@/ })
USER=${USER_AND_IP_ADDRESS[0]}
IP_ADDRESS=${USER_AND_IP_ADDRESS[1]}

if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "SSH key not found at $SSH_KEY_PATH" >&2
  exit 1
fi

if [ ! $USER ]; then
  echo "Error: User is required" >&2
  print_usage
fi

if [ ! $IP_ADDRESS ]; then
  echo "Error: IP address is required" >&2
  print_usage
fi

# Ensure the current IPv4 address is whitelisted for SSH access
"${SCRIPT_DIR}/allow-private-ssh.sh" "${IP_ADDRESS}"

echo "[Connect] Connecting to $USER@$IP_ADDRESS"
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "$USER@$IP_ADDRESS"