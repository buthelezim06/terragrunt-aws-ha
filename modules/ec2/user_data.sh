#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

ENVIRONMENT="${environment}"
REGION="${region}"
IS_MANAGER="${is_manager}"

SSM_MANAGER_IP="/$ENVIRONMENT/swarm/manager-ip"
SSM_JOIN_TOKEN="/$ENVIRONMENT/swarm/worker-join-token"

# --- Install Docker ---
dnf install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user

# --- Own private IP via IMDSv2 ---
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

if [ "$IS_MANAGER" = "true" ]; then
  # --- Bootstrap the swarm and publish the join token for workers ---
  docker swarm init --advertise-addr "$PRIVATE_IP"

  WORKER_TOKEN=$(docker swarm join-token -q worker)

  aws ssm put-parameter --region "$REGION" \
    --name "$SSM_MANAGER_IP" --value "$PRIVATE_IP" \
    --type String --overwrite

  aws ssm put-parameter --region "$REGION" \
    --name "$SSM_JOIN_TOKEN" --value "$WORKER_TOKEN" \
    --type SecureString --overwrite

  echo "Swarm manager initialised at $PRIVATE_IP"
else
  # --- Wait for the manager to publish its join token, then join ---
  for i in $(seq 1 30); do
    MANAGER_IP=$(aws ssm get-parameter --region "$REGION" \
      --name "$SSM_MANAGER_IP" --query 'Parameter.Value' --output text 2>/dev/null || true)
    JOIN_TOKEN=$(aws ssm get-parameter --region "$REGION" \
      --name "$SSM_JOIN_TOKEN" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || true)

    if [ -n "$MANAGER_IP" ] && [ -n "$JOIN_TOKEN" ] && [ "$MANAGER_IP" != "None" ]; then
      break
    fi
    echo "Waiting for swarm manager to be ready (attempt $i/30)..."
    sleep 10
  done

  if [ -z "$${MANAGER_IP:-}" ] || [ -z "$${JOIN_TOKEN:-}" ]; then
    echo "ERROR: manager never published join token, giving up" >&2
    exit 1
  fi

  docker swarm join --token "$JOIN_TOKEN" "$MANAGER_IP:2377"
  echo "Joined swarm at $MANAGER_IP as worker"
fi
