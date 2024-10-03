#!/bin/bash

# Log the output for debugging purposes
exec > >(tee /var/log/guac-docker-install.log|logger -t guac-docker-install -s 2>/dev/console) 2>&1

# Install required packages
echo "Updating packages and installing required software..."
sudo apt-get update -y
sudo apt-get install -y docker.io docker-compose

# Create a directory for Docker Compose
echo "Creating directory for Docker Compose..."
mkdir -p /home/azureuser/guacamole

# Create a Docker Compose file
echo "Creating Docker Compose file for Guacamole deployment..."
cat <<EOF > /home/azureuser/guacamole/docker-compose.yml
version: '3'
services:
  guacd:
    image: guacamole/guacd
    container_name: guacd
    restart: always
    ports:
      - "4822:4822"

  guacamole:
    image: guacamole/guacamole
    container_name: guacamole
    restart: always
    ports:
      - "8080:8080"
    environment:
      MYSQL_HOSTNAME: "${MYSQL_HOST}"
      MYSQL_PORT: "3306"
      MYSQL_DATABASE: "${MYSQL_DB_NAME}"
      MYSQL_USER: "${MYSQL_USERNAME}"
      MYSQL_PASSWORD: "${MYSQL_PASSWORD}"
      GUACAMOLE_HOME: "/etc/guacamole"
      GUACAMOLE_USERNAME: "guacadmin"
      GUACAMOLE_PASSWORD: "guacadmin"
    depends_on:
      - guacd
EOF

# Set correct permissions
sudo chown -R azureuser:azureuser /home/azureuser/guacamole

# Change to the directory
cd /home/azureuser/guacamole

# Start the Docker Compose services
echo "Starting Docker Compose services..."
sudo docker-compose up -d

echo "Guacamole setup complete."
