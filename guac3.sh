#!/bin/bash

# Suppress debconf frontend warnings
export DEBIAN_FRONTEND=noninteractive

# MySQL connection parameters
MYSQL_HOST="$1"
MYSQL_USER="$2"
MYSQL_PASSWORD="$3"
MYSQL_DB="$4"
GUACADMIN_PASSWORD="$5"

# Set Docker image versions
GUACD_IMAGE="guacamole/guacd:1.5.5"
GUACAMOLE_IMAGE="guacamole/guacamole:1.5.5"

# Logging the MySQL connection details for verification
echo "Connecting to MySQL with:"
echo "  MYSQL_HOST: $MYSQL_HOST"
echo "  MYSQL_USER: $MYSQL_USER"
echo "  MYSQL_DB: $MYSQL_DB"

# Ensure Docker is installed
echo "Installing Docker if not already installed..."
apt-get update -y && apt-get install -y docker.io

# Verify MySQL connection and database existence
echo "Verifying MySQL connection and database existence..."
if ! mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "USE $MYSQL_DB" 2>/dev/null; then
    echo "Error: Unable to connect to MySQL or database '$MYSQL_DB' does not exist. Please check MySQL details."
    exit 1
fi

# Pull Docker images if not already pulled
echo "Pulling Docker images for Guacamole..."
docker pull $GUACD_IMAGE
docker pull $GUACAMOLE_IMAGE

# Check if the Guacamole schema has already been applied
echo "Checking if Guacamole schema already exists in MySQL database..."
TABLE_EXISTS=$(mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -D "$MYSQL_DB" -e "SHOW TABLES LIKE 'guacamole_connection_group';" | grep -c 'guacamole_connection_group')

if [ "$TABLE_EXISTS" -eq 0 ]; then
    echo "Applying Guacamole schema to MySQL database..."
    cat /opt/guacamole/schema/*.sql | mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DB"
    echo "Schema applied successfully."
else
    echo "Schema already exists, skipping schema application."
fi

# Run Guacamole and Guacd containers
echo "Starting Guacamole and Guacd containers..."
docker run --name guacd --restart always -d $GUACD_IMAGE
docker run --name guacamole --restart always -d --link guacd:guacd \
    -e MYSQL_HOSTNAME="$MYSQL_HOST" \
    -e MYSQL_DATABASE="$MYSQL_DB" \
    -e MYSQL_USER="$MYSQL_USER" \
    -e MYSQL_PASSWORD="$MYSQL_PASSWORD" \
    -e GUACAMOLE_HOME="/etc/guacamole" \
    -e GUACADMIN_PASSWORD="$GUACADMIN_PASSWORD" \
    -p 8080:8080 $GUACAMOLE_IMAGE

echo "Guacamole deployment completed successfully."
