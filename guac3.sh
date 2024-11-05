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

# === System Updates & Docker Installation ===
echo "Updating system packages and installing Docker..."
apt-get update -y && apt-get install -y docker.io

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

# === MySQL Schema Setup ===
echo "Checking if Guacamole schema is already present in MySQL..."
TABLE_EXISTS=$(mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -D "$MYSQL_DB" -e "SHOW TABLES LIKE 'guacamole_connection_group';" | grep -c 'guacamole_connection_group')

if [ "$TABLE_EXISTS" -eq 0 ]; then
    echo "Applying Guacamole schema to MySQL..."
    cat /opt/guacamole/schema/*.sql | mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DB"
    echo "Schema applied successfully."
else
    echo "Schema already exists, skipping schema application."
fi

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
