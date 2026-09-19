#!/bin/bash

set -e

# ============================================================
# SIENNA CENTRAL
# ELK-based SIEM deployment
#
# Target:
#   Amazon Linux EC2
#   16 GB RAM
#
# Memory allocation:
#   Elasticsearch: 6 GB JVM / 8 GB container
#   Logstash:      2 GB JVM / 3 GB container
#   Kibana:        1 GB JVM / 2 GB container
# ============================================================

echo "============================================================"
echo "              SIENNA CENTRAL - INITIALIZING"
echo "============================================================"

# ------------------------------------------------------------
# 1. System update
# ------------------------------------------------------------

echo "[1/9] Updating system..."

yum update -y


# ------------------------------------------------------------
# 2. Install Docker
# ------------------------------------------------------------

echo "[2/9] Installing Docker..."

yum install -y docker curl 

systemctl enable docker
systemctl start docker

echo "Docker version:"
docker --version


# ------------------------------------------------------------
# 3. Install Docker Compose
# ------------------------------------------------------------

echo "[3/9] Installing Docker Compose..."

COMPOSE_VERSION="v2.39.2"

curl -SL \
  "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-aarch64" \
  -o /usr/local/bin/docker-compose

chmod +x /usr/local/bin/docker-compose

docker-compose version


# ------------------------------------------------------------
# 4. Configure Elasticsearch kernel settings
# ------------------------------------------------------------

echo "[4/9] Configuring Elasticsearch..."

cat > /etc/sysctl.d/99-sienna-elasticsearch.conf <<EOF
vm.max_map_count=262144
EOF

sysctl --system


# ------------------------------------------------------------
# 5. Create Sienna Central directory structure
# ------------------------------------------------------------

echo "[5/9] Creating Sienna Central directories..."

mkdir -p /opt/sienna-central
mkdir -p /opt/sienna-central/logstash/pipeline
mkdir -p /opt/sienna-central/elasticsearch/data

cd /opt/sienna-central


# ------------------------------------------------------------
# Generate credentials
# ------------------------------------------------------------

echo "Generating Elasticsearch credentials..."

ELASTIC_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
KIBANA_SYSTEM_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)

export ELASTIC_PASSWORD
export KIBANA_SYSTEM_PASSWORD

# Store credentials so they can be retrieved later.
# Root-only access.
cat > /root/sienna-central-credentials.txt <<EOF
SIENNA CENTRAL CREDENTIALS
==========================

Elastic user:
Username: elastic
Password: ${ELASTIC_PASSWORD}

Kibana system user:
Username: kibana_system
Password: ${KIBANA_SYSTEM_PASSWORD}
EOF

chmod 600 /root/sienna-central-credentials.txt


# ------------------------------------------------------------
# 6. Create Docker Compose configuration
# ------------------------------------------------------------

echo "[6/9] Creating docker-compose.yml..."

cat > /opt/sienna-central/docker-compose.yml <<'EOF'

services:

  # ==========================================================
  # ELASTICSEARCH
  # ==========================================================

  elasticsearch:

    image: docker.elastic.co/elasticsearch/elasticsearch:9.5.4

    container_name: sienna-elasticsearch

    restart: unless-stopped

    environment:
      - discovery.type=single-node
      - xpack.security.enabled=true

      # Initial password for the built-in elastic user
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}

      # 6 GB Elasticsearch JVM heap
      - ES_JAVA_OPTS=-Xms6g -Xmx6g

    volumes:
      - elasticsearch-data:/usr/share/elasticsearch/data

    ports:
      - "9200:9200"

    networks:
      - sienna

    mem_limit: 8g


  # ==========================================================
  # LOGSTASH
  # ==========================================================

  logstash:

    image: docker.elastic.co/logstash/logstash:9.5.4

    container_name: sienna-logstash

    restart: unless-stopped

    environment:

      # 2 GB Logstash JVM heap
      - LS_JAVA_OPTS=-Xms2g -Xmx2g

      # Password used by Logstash to authenticate to Elasticsearch
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}

    volumes:
      - ./logstash/pipeline:/usr/share/logstash/pipeline:ro

    ports:
      - "5044:5044"
      - "5000:5000"

    depends_on:
      - elasticsearch

    networks:
      - sienna

    mem_limit: 3g


  # ==========================================================
  # KIBANA
  # ==========================================================

  kibana:

    image: docker.elastic.co/kibana/kibana:9.5.4

    container_name: sienna-kibana

    restart: unless-stopped

    environment:

      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=${KIBANA_SYSTEM_PASSWORD}

      - XPACK_SECURITY_ENCRYPTIONKEY=srCFWMjkGBRqTFkVhovjVgvNcTHJ1ch4
      - XPACK_REPORTING_ENCRYPTIONKEY=1HVyNaReKIdyLXbTLWuWfbWAZHIhgjGu
      - XPACK_ENCRYPTEDSAVEDOBJECTS_ENCRYPTIONKEY=dV4On8vDyxE7qBhfDIQq9VY7WYqoGwIj

    ports:
      - "127.0.0.1:5601:5601"

    depends_on:
      - elasticsearch

    networks:
      - sienna

    mem_limit: 2g


# ============================================================
# NETWORK
# ============================================================

networks:

  sienna:

    driver: bridge


# ============================================================
# PERSISTENT STORAGE
# ============================================================

volumes:

  elasticsearch-data:

EOF


# ------------------------------------------------------------
# 7. Create Logstash pipeline
# ------------------------------------------------------------

echo "[7/9] Creating Logstash pipeline..."

cat > /opt/sienna-central/logstash/pipeline/logstash.conf <<'EOF'

input {

  # Filebeat / Beats agents
  beats {
    port => 5044
  }

  # JSON events sent over TCP
  tcp {
    port => 5000
    codec => json
  }

}


filter {

  # ----------------------------------------------------------
  # Detection / parsing rules will go here
  # ----------------------------------------------------------

}


output {

  # Debug output
  stdout {
    codec => rubydebug
  }

  # Send events to Elasticsearch
  elasticsearch {

    hosts => [
      "http://elasticsearch:9200"
    ]

    user => "elastic"
    password => "${ELASTIC_PASSWORD}"

    index => "sienna-central-%{+YYYY.MM.dd}"

  }

}

EOF


# ------------------------------------------------------------
# 8. Pull images
# ------------------------------------------------------------

echo "[8/9] Pulling ELK images..."

docker pull docker.elastic.co/elasticsearch/elasticsearch:9.5.4

docker pull docker.elastic.co/logstash/logstash:9.5.4

docker pull docker.elastic.co/kibana/kibana:9.5.4


# ------------------------------------------------------------
# 9. Start Sienna Central
# ------------------------------------------------------------

echo "[9/9] Starting Sienna Central..."

cd /opt/sienna-central

docker-compose up -d


# ------------------------------------------------------------
# Give Elasticsearch some time to initialize
# ------------------------------------------------------------

echo ""
echo "Waiting for Elasticsearch..."

for i in {1..60}; do

    if curl -s http://localhost:9200 >/dev/null 2>&1; then

        echo "Elasticsearch is UP."

        break

    fi

    echo "Waiting... ($i/60)"

    sleep 5

done


# ------------------------------------------------------------
# Set kibana_system password
# ------------------------------------------------------------

echo ""
echo "Configuring kibana_system password..."

for i in {1..30}; do

    if curl -s \
        -u "elastic:${ELASTIC_PASSWORD}" \
        http://localhost:9200/_security/user/kibana_system \
        >/dev/null 2>&1; then

        echo "Elasticsearch security API is available."

        break

    fi

    echo "Waiting for Elasticsearch security API... ($i/30)"

    sleep 5

done


curl -sS \
  -X POST \
  -u "elastic:${ELASTIC_PASSWORD}" \
  -H "Content-Type: application/json" \
  "http://localhost:9200/_security/user/kibana_system/_password" \
  -d "{\"password\":\"${KIBANA_SYSTEM_PASSWORD}\"}" \
  >/dev/null

echo "kibana_system password configured."


# ------------------------------------------------------------
# Restart stack so Kibana receives the credentials
# ------------------------------------------------------------

echo ""
echo "Restarting Sienna Central services..."

docker-compose up -d


# ------------------------------------------------------------
# Display deployment status
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo "              SIENNA CENTRAL DEPLOYED"
echo "============================================================"

docker ps

TOKEN=$(curl -sX PUT \
  -H "X-aws-ec2-metadata-token-ttl-seconds:21600" \
  http://169.254.169.254/latest/api/token)

PUBLIC_IP=$(curl -s \
  -H "X-aws-ec2-metadata-token:${TOKEN}" \
  http://169.254.169.254/latest/meta-data/public-ipv4)

echo ""
echo "Elasticsearch:"
echo "http://${PUBLIC_IP}:9200"

echo ""
echo "Kibana:"
echo "http://${PUBLIC_IP}:5601"

echo ""
echo "Logstash Beats:"
echo "${PUBLIC_IP}:5044"

echo ""
echo "Credentials saved to:"
echo "/root/sienna-central-credentials.txt"

echo ""
echo "============================================================"
echo "              DEPLOYMENT COMPLETE"
echo "============================================================"


echo "[10/10] Installing and configuring Nginx..."

# Install Nginx
amazon-linux-extras install nginx1 -y

# Create Sienna Central Nginx configuration
cat > /etc/nginx/conf.d/sienna.conf <<'EOF'
server {
    listen 80;
    server_name sienna-central.valdron.dev;

    location / {
        proxy_pass http://127.0.0.1:5601;

        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# Remove the default Nginx configuration if present
rm -f /etc/nginx/conf.d/default.conf

# Allow Nginx to connect to Kibana
setsebool -P httpd_can_network_connect 1

# Validate Nginx configuration
nginx -t

# Enable and start Nginx
systemctl enable nginx
systemctl start nginx

echo "Nginx status:"
systemctl is-active nginx

echo ""
echo "Testing local Nginx → Kibana connection..."
curl -I -H "Host: sienna-central.valdron.dev" http://127.0.0.1

echo ""
echo "Nginx is serving Sienna Central on port 80."
