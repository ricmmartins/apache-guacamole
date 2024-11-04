#!/bin/bash

# === Script Variables ===
MYSQL_HOST=""
MYSQL_USER=""
MYSQL_PASSWORD=""
MYSQL_DB=""
GUAC_PORT="8080"
GUAC_VERSION="1.5.5"

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

# Check if the database exists
DB_EXISTS=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -e "SHOW DATABASES LIKE '$MYSQL_DB';" | grep "$MYSQL_DB" > /dev/null; echo "$?")

if [ "$DB_EXISTS" -ne 0 ]; then
    echo "Database $MYSQL_DB does not exist. Creating database..."
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -e "CREATE DATABASE $MYSQL_DB;"
fi

# === Check if Guacamole Tables Exist ===
TABLE_COUNT=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -D $MYSQL_DB -e "SHOW TABLES;" | wc -l)

if [ "$TABLE_COUNT" -eq 0 ]; then
    echo "No tables found in $MYSQL_DB. Importing schema..."
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" $MYSQL_DB < /opt/guacamole-initdb.sql

    if [ $? -ne 0 ]; then
        echo "Failed to import the schema. Please check MySQL connection details and schema file."
        exit 1
    fi
    echo "Schema imported successfully into $MYSQL_DB."
else
    echo "Guacamole tables already exist in $MYSQL_DB. Skipping schema import."
fi

# === Set Default Admin Username and Password ===
USER_COUNT=$(mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -D $MYSQL_DB -e "SELECT COUNT(*) FROM guacamole_user;" | tail -n 1)

if [ "$USER_COUNT" -eq 0 ]; then
    echo "No existing users found. Creating default admin user 'guacadmin' with password 'guacadmin'."
    SQL_COMMAND="
    USE $MYSQL_DB;
    INSERT INTO guacamole_user (username, password_salt, password_hash, disabled, expired, access_window_start, access_window_end, valid_from, valid_until) VALUES ('guacadmin', UNHEX(SHA2(UUID(), 256)), UNHEX(SHA2(CONCAT('guacadmin', SHA2(UUID(), 256)), 256)), 0, 0, 0, 0, 0, 0);
    INSERT INTO guacamole_user_permission (entity_id, permission) SELECT user_id, 'READ' FROM guacamole_user WHERE username='guacadmin';
    INSERT INTO guacamole_system_permission (entity_id, permission) SELECT user_id, 'ADMINISTER' FROM guacamole_user WHERE username='guacadmin';
    "
    mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -e "$SQL_COMMAND"

    if [ $? -eq 0 ]; then
        echo "Default admin user 'guacadmin' created successfully."
    else
        echo "Failed to create default admin user. Please check database configuration."
    fi
else
    echo "Users already exist in the database. Skipping default admin creation."
fi

# === Ensure Docker Containers are Running ===
docker restart guacd
docker restart guacamole

echo "Guacamole setup for version $GUAC_VERSION completed successfully."
