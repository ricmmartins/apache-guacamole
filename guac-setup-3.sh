#!/bin/bash

# Variables passed as arguments
MYSQL_HOST="$1"
MYSQL_DB="$2"
MYSQL_USER="$3"
MYSQL_PASSWORD="$4"
GUACADMIN_PASSWORD="$5"

# Install necessary packages
sudo apt-get update
sudo apt-get install -y docker.io docker-compose mysql-client-core-5.7

# Enable and start Docker
sudo systemctl enable docker
sudo systemctl start docker

# Create Guacamole configuration directory
sudo mkdir -p /etc/guacamole

# Create guacamole.properties
sudo bash -c "cat > /etc/guacamole/guacamole.properties" <<EOL
mysql-hostname: $MYSQL_HOST
mysql-port: 3306
mysql-database: $MYSQL_DB
mysql-username: $MYSQL_USER
mysql-password: $MYSQL_PASSWORD
EOL

# Adjust permissions
sudo chown -R $ADMIN_USERNAME:$ADMIN_USERNAME /etc/guacamole

# Create Docker Compose file
sudo bash -c "cat > /home/$ADMIN_USERNAME/docker-compose.yml" <<EOL
version: "3"
services:
  guacd:
    image: guacamole/guacd
    container_name: guacd
    ports:
      - "4822:4822"

  guacamole:
    image: guacamole/guacamole
    container_name: guacamole
    depends_on:
      - guacd
    ports:
      - "8080:8080"
    volumes:
      - /etc/guacamole:/etc/guacamole
EOL

# Adjust permissions
sudo chown $ADMIN_USERNAME:$ADMIN_USERNAME /home/$ADMIN_USERNAME/docker-compose.yml

# Start Docker Compose
cd /home/$ADMIN_USERNAME
sudo docker-compose up -d

# Wait for Guacamole to be ready
sleep 30

# Download Guacamole schema
sudo docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --mysql > initdb.sql

# Import schema into MySQL
mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DB < initdb.sql

# Create guacadmin user with specified password
HASHED_PASSWORD=$(echo -n "$GUACADMIN_PASSWORD" | openssl md5 | awk '{print $2}')
mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DB <<EOF
INSERT INTO guacamole_user (username, password_hash, password_salt, disabled, expired, access_window_start, access_window_end, valid_from, valid_until, timezone) VALUES ('guacadmin', UNHEX('$HASHED_PASSWORD'), UNHEX(''), 0, 0, NULL, NULL, NULL, NULL, '');
INSERT INTO guacamole_user_permission (user_id, affected_user_id, permission) SELECT user_id, user_id, 'READ' FROM guacamole_user WHERE username='guacadmin';
INSERT INTO guacamole_system_permission (user_id, permission) SELECT user_id, 'ADMINISTER' FROM guacamole_user WHERE username='guacadmin';
EOF

# Restart Guacamole container
sudo docker restart guacamole
