data "aws_ami" "main" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

data "aws_vpc" "main" {
  default = true
}

data "http" "MY_IP" {
  url = "https://checkip.amazonaws.com"
}


data "external" "remote_elk_password" {
  program = ["bash", "-c", <<EOF
    set -u

    ip="${aws_instance.main.public_ip}"
    key_path="${path.module}/SSH_Keys/sienna-central"
    max_attempts=15
    attempt=1
    file_content=""

    # Wait until SSH is available and the credentials file can be read.
    while [ "$${attempt}" -le "$${max_attempts}" ]; do
      file_content="$(ssh -i "$${key_path}" \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        "ec2-user@$${ip}" \
        "sudo cat /root/sienna-central-credentials.txt" 2>/dev/null || true)"

      if [ -n "$${file_content}" ]; then
        break
      fi

      sleep 5
      attempt=$((attempt + 1))
    done

    if [ -z "$${file_content}" ]; then
      echo "Timed out waiting for SSH daemon or credentials file to become available on the EC2 instance." >&2
      exit 1
    fi

    # Extract the first non-whitespace value following "Password:".
    elastic_pass="$(printf '%s\n' "$${file_content}" | awk '
      /Elastic user:/ { in_elastic_block = 1 }
      in_elastic_block && /Password:/ {
        sub(/^.*Password:[[:space:]]*/, "")
        print $1
        exit
      }
    ')"

    if [ -z "$${elastic_pass}" ]; then
      echo "Could not parse Elastic password from the credentials file." >&2
      exit 1
    fi

    # Wait until Elasticsearch responds on port 9200.
    container_ready=false
    docker_attempts=60
    docker_attempt=1

    while [ "$${docker_attempt}" -le "$${docker_attempts}" ]; do
      response="$(ssh -i "$${key_path}" \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        "ec2-user@$${ip}" \
        "curl -s -o /dev/null -w '%%{http_code}' http://localhost:9200" 2>/dev/null || true)"

      case "$${response}" in
        200|301|302|401)
          container_ready=true
          break
          ;;
      esac

      sleep 5
      docker_attempt=$((docker_attempt + 1))
    done

    if [ "$${container_ready}" != true ]; then
      echo "Timed out waiting for Elasticsearch Docker container to bind to port 9200." >&2
      exit 1
    fi

    # The generated password is a non-whitespace token, so it is safe to quote
    # directly in the JSON response expected by the external data source.
    printf '{"password":"%s"}\n' "$${elastic_pass}"
EOF
  ]

  depends_on = [aws_instance.main]
}
