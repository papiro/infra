#!/usr/bin/env bash
# This script opens SSH access to the current IPv4 address for the given EC2 instance security group.
#
# Steps performed:
#   1. Detect the caller's IPv4 address using https://ipv4.icanhazip.com/.
#   2. Locate the EC2 instance by public IP address.
#   3. Add an ingress rule on the instance's primary security group to allow TCP/22 from that IPv4 /32,
#      if such a rule is not already present.
#
# Requirements:
#   • AWS CLI v2 configured with credentials that can modify EC2 security groups.
#   • curl
#
# Usage:
#   ./allow-private-ssh.sh <IP_ADDRESS>
#
set -euo pipefail

IP_ADDRESS=${1-}

if [[ -z "${IP_ADDRESS}" ]]; then
  echo "[SSH Access] Error: IP address is required." >&2
  exit 1
fi

########################################
# 1. Detect current public IPv4 address
########################################
echo "[SSH Access] Detecting current IPv4 address…"
CURRENT_IPV4=$(curl -4 -s https://ipv4.icanhazip.com/ | tr -d '\n')

if [[ -z "${CURRENT_IPV4}" ]]; then
  echo "[SSH Access] Error: Unable to determine IPv4 address." >&2
  exit 1
fi

CIDR="${CURRENT_IPV4}/32"
echo "[SSH Access] Current IPv4: ${CIDR}"

########################################
# 2. Locate the EC2 instance            
########################################

echo "[SSH Access] Locating EC2 instance with public IP ${IP_ADDRESS}"
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=ip-address,Values=${IP_ADDRESS}" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [[ "${INSTANCE_ID}" == "None" || "${INSTANCE_ID}" == "" ]]; then
  echo "[SSH Access] Error: Instance with public IP ${IP_ADDRESS} not found." >&2
  exit 1
fi

SECURITY_GROUP_ID=$(aws ec2 describe-instances \
  --instance-ids "${INSTANCE_ID}" \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text)

echo "[SSH Access] InstanceId: ${INSTANCE_ID}, SecurityGroupId: ${SECURITY_GROUP_ID}"

########################################
# 3. Replace any existing IPv4 ingress for port 22 with the new one
########################################

# Gather existing IPv4 CIDRs for port 22 (if any)
EXISTING_CIDRS=$(aws ec2 describe-security-groups \
  --group-ids "${SECURITY_GROUP_ID}" \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`22\` && ToPort==\`22\` && IpProtocol=='tcp'].IpRanges[].CidrIp" \
  --output text)

# If our current CIDR is already authorized, no action is needed
if [[ " ${EXISTING_CIDRS} " == *" ${CIDR} "* ]]; then
  echo "[SSH Access] Current CIDR ${CIDR} already authorized. No changes required."
  exit 0
fi

# # Revoke old rules
if [[ -n "${EXISTING_CIDRS}" ]]; then
  for OLD_CIDR in ${EXISTING_CIDRS}; do
    echo "[SSH Access] Revoking old IPv4 ingress ${OLD_CIDR}…"
    aws ec2 revoke-security-group-ingress \
      --group-id "${SECURITY_GROUP_ID}" \
      --protocol tcp \
      --port 22 \
      --cidr "${OLD_CIDR}"
  done
fi

# Add the current IPv4 ingress rule
echo "[SSH Access] Authorizing ingress for ${CIDR}…"
aws ec2 authorize-security-group-ingress \
  --group-id "${SECURITY_GROUP_ID}" \
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${CIDR},Description='Developer SSH access'}]"

echo "[SSH Access] Ingress rule updated."
