#!/bin/bash

# === Variables Configuration ===
MYSQL_HOST=${MYSQL_HOST:-"mysql_server"}
MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_DB=${MYSQL_DB:-"guacdb"}
MYSQL_USER=${MYSQL_USER:-"guacadmin"}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
GUACADMIN_PASSWORD=${GUACADMIN_PASSWORD}

# Docker image tags for stable deployments
GUACAMOLE_IMAGE="guacamole/guacamole:latest"
GUACAMOLE_MYSQL_IMAGE="guacamole/guacamole-auth-jdbc-mysql:latest"
MYSQL_IMAGE="mysql:8.0"

# Check if MySQL password and Guacamole admin password are provided
if [ -z "$MYSQL_PASSWORD" ] || [ -z "$GUACADMIN_PASSWORD" ]; then
  echo "ERROR: MYSQL_PASSWORD and GUACADMIN_PASSWORD must be set."
  exit 1
fi

# Pull Docker images
docker pull $GUACAMOLE_IMAGE
docker pull $GUACAMOLE_MYSQL_IMAGE
docker pull $MYSQL_IMAGE

# Start MySQL container
docker run --name guac-mysql -e MYSQL_ROOT_PASSWORD="$MYSQL_PASSWORD" \
  -e MYSQL_DATABASE="$MYSQL_DB" -e MYSQL_USER="$MYSQL_USER" -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
  -d --network=guac-network $MYSQL_IMAGE

# Wait for MySQL to initialize and import schema if necessary
echo "Waiting for MySQL to initialize..."
sleep 15

docker exec -i guac-mysql mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DB <<EOF
CREATE TABLE IF NOT EXISTS guacamole_user (username VARCHAR(128) PRIMARY KEY);
EOF

# Start Guacamole with the MySQL authentication extension
docker run --name guacamole -d --network=guac-network -e MYSQL_HOSTNAME="$MYSQL_HOST" \
  -e MYSQL_PORT="$MYSQL_PORT" -e MYSQL_DATABASE="$MYSQL_DB" -e MYSQL_USERNAME="$MYSQL_USER" \
  -e MYSQL_PASSWORD="$MYSQL_PASSWORD" -e GUACAMOLE_HOME="/etc/guacamole" \
  -e GUACADMIN_PASSWORD="$GUACADMIN_PASSWORD" -p 8080:8080 $GUACAMOLE_IMAGE
