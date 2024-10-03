#!/bin/bash

# === Script Variables ===
MYSQL_HOST=""
MYSQL_USER=""
MYSQL_PASSWORD=""
MYSQL_DB=""
GUAC_PORT="8080"

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
apt-get update && apt-get install -y docker.io wget

# === Run Guacamole and guacd Containers ===
docker run --name guacd -d guacamole/guacd
docker run --name guacamole --link guacd:guacd -e MYSQL_HOSTNAME=$MYSQL_HOST \
  -e MYSQL_PORT=3306 -e MYSQL_DATABASE=$MYSQL_DB -e MYSQL_USER=$MYSQL_USER \
  -e MYSQL_PASSWORD=$MYSQL_PASSWORD -d -p $GUAC_PORT:8080 guacamole/guacamole

# === Download and Import the Guacamole Schema ===
# Download schema file
wget https://raw.githubusercontent.com/apache/guacamole-client/master/extensions/guacamole-auth-jdbc/modules/guacamole-auth-jdbc-mysql/schema/001-create-schema.sql -O /opt/guacamole-initdb.sql

# Wait for the MySQL server to be ready before attempting schema import
echo "Waiting for MySQL server to be ready..."
until mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; do
    sleep 5
    echo "Trying to connect to MySQL server..."
done

# Import the schema
echo "Importing the Guacamole schema into database $MYSQL_DB..."
mysql -h $MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" $MYSQL_DB < /opt/guacamole-initdb.sql

# === Ensure Docker Containers are Running ===
docker start guacd
docker start guacamole

echo "Guacamole setup completed successfully."
