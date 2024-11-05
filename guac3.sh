#!/bin/bash

# === Initialization ===
export DEBIAN_FRONTEND=noninteractive

# Define log file for deployment progress tracking
LOG_FILE="/var/log/guac_deployment.log"
exec > >(tee -a $LOG_FILE) 2>&1

# === MySQL Connection Parameters ===
MYSQL_HOST="$1"
MYSQL_USER="$2"
MYSQL_PASSWORD="$3"
MYSQL_DB="$4"
GUACADMIN_PASSWORD="$5"

# Docker image tags
GUACD_IMAGE="guacamole/guacd:1.5.5"
GUACAMOLE_IMAGE="guacamole/guacamole:1.5.5"

# === System Updates & Package Installation ===
echo "Updating system packages and installing Docker and MySQL client..."
apt-get update -y && apt-get install -y docker.io mysql-client wget

# === Download the Guacamole Schema for Version 1.5.5 ===
SCHEMA_URL="https://raw.githubusercontent.com/apache/guacamole-client/1.5.5/extensions/guacamole-auth-jdbc/modules/guacamole-auth-jdbc-mysql/schema/001-create-schema.sql"
SCHEMA_FILE="/opt/guacamole-initdb.sql"
echo "Downloading Guacamole schema..."
wget $SCHEMA_URL -O $SCHEMA_FILE

# === MySQL Schema Application ===
echo "Applying Guacamole schema to MySQL..."
mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DB" < $SCHEMA_FILE
echo "Schema applied successfully."

# === MySQL Connection Verification ===
echo "Validating MySQL connection parameters..."
if ! mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "USE $MYSQL_DB" 2>/dev/null; then
    echo "MySQL connection failed: database '$MYSQL_DB' not accessible. Check MySQL parameters."
    exit 1
fi

# === Docker Images Pulling ===
echo "Pulling Docker images for Guacamole..."
docker pull $GUACD_IMAGE
docker pull $GUACAMOLE_IMAGE

# === Guacamole & Guacd Container Launch ===
echo "Launching Guacamole and Guacd containers..."
docker run --name guacd --restart always -d $GUACD_IMAGE
docker run --name guacamole --restart always -d --link guacd:guacd \
    -e MYSQL_HOSTNAME="$MYSQL_HOST" \
    -e MYSQL_DATABASE="$MYSQL_DB" \
    -e MYSQL_USER="$MYSQL_USER" \
    -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
    -e GUACADMIN_PASSWORD="$GUACADMIN_PASSWORD" \
    -p 8080:8080 $GUACAMOLE_IMAGE

echo "Apache Guacamole setup completed."
echo "Login credentials:"
echo "  Username: guacadmin"
echo "  Password: $GUACADMIN_PASSWORD"
