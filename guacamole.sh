#!/bin/bash

# === Script Variables ===
MYSQL_HOST=""
MYSQL_USER=""
MYSQL_PASSWORD=""
MYSQL_DB=""
GUAC_PORT="8080"
ADMIN_USER="guacadmin"
ADMIN_PASS=${GUAC_ADMIN_PASSWORD:-"guacadmin"}  # Allow setting admin password externally

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

# === Install Docker and Dependencies ===
echo "Installing Docker and required packages..."
apt-get update -y && apt-get install -y docker.io wget mysql-client
systemctl start docker || { echo "Failed to start Docker"; exit 1; }

# === Run Guacamole and guacd Containers ===
echo "Setting up Docker containers for Guacamole..."
docker run --name guacd -d guacamole/guacd || { echo "Failed to start guacd container"; exit 1; }
docker run --name guacamole --link guacd:guacd -e MYSQL_HOSTNAME=$MYSQL_HOST \
  -e MYSQL_PORT=3306 -e MYSQL_DATABASE=$MYSQL_DB -e MYSQL_USER=$MYSQL_USER \
  -e MYSQL_PASSWORD=$MYSQL_PASSWORD -d -p $GUAC_PORT:8080 guacamole/guacamole || { echo "Failed to start guacamole container"; exit 1; }

# === Download the Guacamole Schema ===
SCHEMA_URL="https://raw.githubusercontent.com/apache/guacamole-client/master/extensions/guacamole-auth-jdbc/modules/guacamole-auth-jdbc-mysql/schema/001-create-schema.sql"
wget $SCHEMA_URL -O /opt/guacamole-initdb.sql || { echo "Failed to download Guacamole schema"; exit 1; }

# === Check MySQL Server Connectivity and Create Database if Missing ===
echo "Checking MySQL server connectivity and database..."
until mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; do
    sleep 5
    echo "Waiting for MySQL server to be ready..."
done

# Check if the database exists
DB_EXISTS=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -e "SHOW DATABASES LIKE '$MYSQL_DB';" | grep "$MYSQL_DB" > /dev/null; echo "$?")

if [ "$DB_EXISTS" -ne 0 ]; then
    echo "Database $MYSQL_DB does not exist. Creating it..."
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -e "CREATE DATABASE $MYSQL_DB;" || { echo "Failed to create database $MYSQL_DB"; exit 1; }
fi

# === Import Guacamole Schema if No Tables Exist ===
TABLE_COUNT=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -D $MYSQL_DB -e "SHOW TABLES;" | wc -l)

if [ "$TABLE_COUNT" -eq 0 ]; then
    echo "No tables found in $MYSQL_DB. Importing schema..."
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" $MYSQL_DB < /opt/guacamole-initdb.sql || { echo "Failed to import schema"; exit 1; }
    echo "Schema imported successfully into $MYSQL_DB."
else
    echo "Schema already exists in $MYSQL_DB. Skipping import."
fi

# === Set Default Admin Username and Password ===
ADMIN_PASS_HASH=$(echo -n "$ADMIN_PASS" | sha256sum | awk '{print $1}')
USER_COUNT=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -D $MYSQL_DB -e "SELECT COUNT(*) FROM guacamole_user;" | tail -n 1)

if [ "$USER_COUNT" -eq 0 ]; then
    echo "Creating default admin user 'guacadmin'."
    SQL_COMMAND="
    USE $MYSQL_DB;
    INSERT INTO guacamole_user (username, password_salt, password_hash, disabled, expired, access_window_start, access_window_end, valid_from, valid_until) VALUES ('guacadmin', UNHEX(SHA2(UUID(), 256)), UNHEX(SHA2(CONCAT('$ADMIN_PASS', SHA2(UUID(), 256)), 256)), 0, 0, 0, 0, 0, 0);
    INSERT INTO guacamole_user_permission (entity_id, permission) SELECT user_id, 'READ' FROM guacamole_user WHERE username='guacadmin';
    INSERT INTO guacamole_system_permission (entity_id, permission) SELECT user_id, 'ADMINISTER' FROM guacamole_user WHERE username='guacadmin';
    "
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -e "$SQL_COMMAND" || { echo "Failed to create default admin user"; exit 1; }
    echo "Admin user 'guacadmin' created."
else
    echo "Users already exist in the database. Skipping default admin creation."
fi

# === Ensure Docker Containers are Running ===
docker restart guacd
docker restart guacamole

echo "Guacamole setup completed successfully."
