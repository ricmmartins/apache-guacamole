#!/bin/bash

# === Parse Input Arguments ===
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --mysql-host) MYSQL_HOST="$2"; shift ;;
        --mysql-user) MYSQL_USER="$2"; shift ;;
        --mysql-password) MYSQL_PASSWORD="$2"; shift ;;
        --mysql-database) MYSQL_DB="$2"; shift ;;
        --port) GUAC_PORT="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# === Install Docker ===
sudo apt update
sudo apt install -y docker.io

# === Pull and Run Docker Containers for Guacamole and MySQL ===
sudo docker run --name guacd -d guacamole/guacd
sudo docker run --name guacamole -d --link guacd:guacd \
  -e MYSQL_HOSTNAME=$MYSQL_HOST -e MYSQL_PORT=3306 \
  -e MYSQL_DATABASE=$MYSQL_DB -e MYSQL_USER=$MYSQL_USER \
  -e MYSQL_PASSWORD=$MYSQL_PASSWORD -p $GUAC_PORT:8080 guacamole/guacamole

echo "Guacamole setup using Docker is complete!"
