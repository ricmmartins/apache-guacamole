#!/bin/bash

# === Script Variables ===
MYSQL_HOST=""
MYSQL_USER=""
MYSQL_PASSWORD=""
MYSQL_DB="guacdb"  # Ensure this matches the database name defined in your setup
GUAC_PORT="8080"
GUAC_VERSION="1.5.5"
ADMIN_PASSWORD=""  # This will be passed as a parameter

# === Parse Input Arguments ===
while [ "$1" != "" ]; do
    case $1 in
        --mysql-host ) shift
                       MYSQL_HOST=$1
                       ;;
        --mysql-user ) shift
                       MYSQL_USER=$1
                       ;;
        --mysql-password ) shift
                           MYSQL_PASSWORD=$1
                           ;;
        --mysql-database ) shift
                           MYSQL_DB=$1
                           ;;
        --port ) shift
                 GUAC_PORT=$1
                 ;;
        --admin-password ) shift
                           ADMIN_PASSWORD=$1
                           ;;
    esac
    shift
done

# === Check for Missing Parameters ===
if [ -z "$MYSQL_HOST" ] || [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASSWORD" ] || [ -z "$MYSQL_DB" ] || [ -z "$ADMIN_PASSWORD" ]; then
    echo "Missing one or more required parameters."
    exit 1
fi

# === Install Docker ===
apt-get update && apt-get install -y docker.io wget mysql-client-core-8.0

# === Pull Specific Version of Guacamole and guacd Images ===
docker pull guacamole/guacd:$GUAC_VERSION
docker pull guacamole/guacamole:$GUAC_VERSION

# === Run Guacamole and guacd Containers ===
docker run --name guacd -d guacamole/guacd:$GUAC_VERSION
docker run --name guacamole --link guacd:guacd -e MYSQL_HOSTNAME=$MYSQL_HOST \
  -e MYSQL_PORT=3306 -e MYSQL_DATABASE=$MYSQL_DB -e MYSQL_USER=$MYSQL_USER \
  -e MYSQL_PASSWORD=$MYSQL_PASSWORD -d -p $GUAC_PORT:8080 guacamole/guacamole:$GUAC_VERSION

# === Generate and Apply Guacamole Schema for MySQL ===
echo "Generating and applying Guacamole schema to MySQL database..."

# Use Guacamole container to generate the initialization script
docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --mysql > /opt/initdb.sql

# Check MySQL server connectivity
until mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SHOW DATABASES;" > /dev/null 2>&1; do
    sleep 5
    echo "Waiting for MySQL server to be ready..."
done

# Ensure 'guacdb' database exists and apply the schema
mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $MYSQL_DB;"
mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DB" < /opt/initdb.sql
if [ $? -ne 0 ]; then
    echo "Failed to apply the schema. Please check MySQL connection details."
    exit 1
fi
echo "Schema applied successfully."

# === Set Default Admin Username and Password ===
echo "Creating default admin user 'guacadmin' with the provided password."
SQL_COMMAND="
USE $MYSQL_DB;
INSERT INTO guacamole_entity (name, type) VALUES ('guacadmin', 'USER') ON DUPLICATE KEY UPDATE entity_id=LAST_INSERT_ID(entity_id);
SET @entity_id = LAST_INSERT_ID();
INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date, disabled, expired, username)
VALUES (@entity_id, UNHEX(SHA2('$ADMIN_PASSWORD', 256)), UNHEX(SHA2(UUID(), 256)), NOW(), 0, 0, 'guacadmin')
ON DUPLICATE KEY UPDATE password_hash=UNHEX(SHA2('$ADMIN_PASSWORD', 256)), password_salt=UNHEX(SHA2(UUID(), 256)), password_date=NOW(), disabled=0, expired=0;
INSERT INTO guacamole_user_permission (entity_id, permission) SELECT user_id, 'READ' FROM guacamole_user WHERE username='guacadmin';
INSERT INTO guacamole_system_permission (entity_id, permission) SELECT user_id, 'ADMINISTER' FROM guacamole_user WHERE username='guacadmin';
"
mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "$SQL_COMMAND"

if [ $? -eq 0 ]; then
    echo "Default admin user 'guacadmin' created successfully."
else
    echo "Failed to create default admin user. Please check database configuration."
fi

# === Ensure Docker Containers are Running ===
docker restart guacd
docker restart guacamole

echo "Guacamole setup for version $GUAC_VERSION completed successfully."
