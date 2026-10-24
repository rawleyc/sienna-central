#!/usr/bin/env bash

set -euo pipefail

auto_approve=false
if [[ "${1:-}" == "--auto-approve" ]]; then
  auto_approve=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--auto-approve]" >&2
  exit 2
fi

iac_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
key_path="$iac_directory/SSH_Keys/sienna-central"

if [[ ! -f "$key_path" ]]; then
  echo "SSH private key not found at $key_path." >&2
  exit 1
fi

for command in terraform ssh jq base64; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

cd "$iac_directory"

get_state_value() {
  local address="$1"
  local property="$2"
  local state
  local value

  if ! state="$(terraform state show "$address")"; then
    echo "Could not read $address from Terraform state." >&2
    return 1
  fi

  value="$(printf '%s\n' "$state" | sed -nE "s/^[[:space:]]*$property[[:space:]]*=[[:space:]]*\"([^\"]+)\"[[:space:]]*$/\1/p" | head -n 1)"
  if [[ -z "$value" ]]; then
    echo "Could not find '$property' in Terraform state for $address." >&2
    return 1
  fi

  printf '%s\n' "$value"
}

run_terraform() {
  terraform "$@"
}

ip="$(get_state_value "aws_instance.main" "public_ip")"
key_id="$(get_state_value "elasticstack_elasticsearch_security_api_key.github_dac_key" "key_id")"

echo "Reading the Elasticsearch password from $ip..."
credentials="$(
  ssh -i "$key_path" \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=no \
    "ec2-user@$ip" \
    "sudo cat /root/sienna-central-credentials.txt"
)"

elastic_password="$(
  printf '%s\n' "$credentials" | awk '
    /Elastic user:/ { in_elastic_block = 1 }
    in_elastic_block && /Password:/ {
      sub(/^.*Password:[[:space:]]*/, "")
      print $1
      exit
    }
  '
)"
if [[ -z "$elastic_password" ]]; then
  echo "Could not parse the Elasticsearch password from the remote credentials file." >&2
  exit 1
fi

request_body="$(jq -cn --arg key_id "$key_id" '{ids: [$key_id]}')"
request_body_base64="$(printf '%s' "$request_body" | base64 -w 0)"

echo "Revoking Elasticsearch API key $key_id..."
revoke_response="$(
  ssh -i "$key_path" \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=no \
    "ec2-user@$ip" \
    "printf '%s' '$request_body_base64' | base64 -d | curl -sS -X DELETE -u 'elastic:$elastic_password' -H 'Content-Type: application/json' --data-binary '@-' http://localhost:9200/_security/api_key"
)"

if ! jq -e --arg key_id "$key_id" \
  '.error_count == 0 and (.invalidated_api_keys | index($key_id) != null)' \
  >/dev/null <<<"$revoke_response"; then
  echo "Elasticsearch did not confirm revocation of API key $key_id. Response: $revoke_response" >&2
  exit 1
fi

verification_response="$(
  ssh -i "$key_path" \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=no \
    "ec2-user@$ip" \
    "curl -sS -u 'elastic:$elastic_password' --get --data-urlencode 'id=$key_id' http://localhost:9200/_security/api_key"
)"

if ! jq -e --arg key_id "$key_id" \
  '.api_keys | any(.[]; .id == $key_id and .invalidated == true)' \
  >/dev/null <<<"$verification_response"; then
  echo "Elasticsearch did not report API key $key_id as invalidated." >&2
  exit 1
fi

echo "Removing the already-revoked API key from Terraform state..."
run_terraform state rm \
  "elasticstack_elasticsearch_security_api_key.github_dac_key"

echo "Destroying the GitHub Actions secret..."
target_args=(destroy "-target=github_actions_secret.kibana_api_key")
if [[ "$auto_approve" == true ]]; then
  target_args+=("-auto-approve")
fi
run_terraform "${target_args[@]}"

echo "Destroying the remaining infrastructure..."
destroy_args=(destroy)
if [[ "$auto_approve" == true ]]; then
  destroy_args+=("-auto-approve")
fi
run_terraform "${destroy_args[@]}"
