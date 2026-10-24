#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$ROOT/terraform"

cd terraform/ && terraform init
terraform -chdir="$TF_DIR" apply -auto-approve
IP=$(terraform -chdir="$TF_DIR" output -raw SIEM_IP)

ANSIBLE_DIR="$ROOT/ansible"
KEY="$ROOT/terraform/SSH_Keys/sienna-central"



cat > "$ANSIBLE_DIR/inventory.ini" <<EOF
[elk_siem]
siem ansible_host=$IP ansible_user=ec2-user ansible_ssh_private_key_file=$KEY
EOF

ansible-playbook \
  -i "$ANSIBLE_DIR/inventory.ini" \
  "$ANSIBLE_DIR/playbook.yml"