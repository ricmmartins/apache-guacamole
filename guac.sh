#!/bin/bash

# === Script Variables ===
MYSQL_HOST=""
MYSQL_USER=""
MYSQL_PASSWORD=""
MYSQL_DB=""
GUAC_PORT="8080"
GUAC_VERSION="1.5.5"

# === Prompt for Admin Password ===
echo -n "Enter the password for the Guacamole admin user: "
read -s ADMIN_PASSWORD
echo

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
    esac
    shift
done

# === Check for Missing Parameters ===
if [ -z "$MYSQL_HOST" ] || [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASSWORD" ] || [ -z "$MYSQL_DB" ]; then
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

# === Download the Guacamole Schema for Version 1.5.5 ===
SCHEMA_URL="https://raw.githubusercontent.com/apache/guacamole-client/1.5.5/extensions/guacamole-auth-jdbc/modules/guacamole-auth-jdbc-mysql/schema/001-create-schema.sql"
wget $SCHEMA_URL -O /opt/guacamole-initdb.sql

# === Check MySQL Server Connectivity and Create Database if Missing ===
echo "Checking MySQL server connectivity and database..."

# Wait for the MySQL server to be ready before attempting schema import
until mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; do
    sleep 5
    echo "Trying to connect to MySQL server..."
done

# Drop and recreate the database to avoid schema conflicts
mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -e "DROP DATABASE IF EXISTS $MYSQL_DB; CREATE DATABASE $MYSQL_DB;"

# Import the schema
mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" $MYSQL_DB < /opt/guacamole-initdb.sql

if [ $? -ne 0 ]; then
    echo "Failed to import the schema. Please check MySQL connection details and schema file."
    exit 1
fi
echo "Schema imported successfully into $MYSQL_DB."

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
mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -e "$SQL_COMMAND"

if [ $? -eq 0 ]; then
    echo "Default admin user 'guacadmin' created successfully."
else
    echo "Failed to create default admin user. Please check database configuration."
fi

# === Ensure Docker Containers are Running ===
docker restart guacd
docker restart guacamole

echo "Guacamole setup for version $GUAC_VERSION completed successfully."