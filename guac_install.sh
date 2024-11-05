#!/bin/bash
LOG_FILE="/var/log/guac_deployment.log"
exec > >(tee -a $LOG_FILE) 2>&1

# Variables
MYSQL_HOST="$1"
MYSQL_USER="$2"
MYSQL_PASSWORD="$3"
MYSQL_DB="$4"
GUACADMIN_PASSWORD="$5"

echo "Starting Apache Guacamole installation at $(date)"
echo "MySQL Host: $MYSQL_HOST, Database: $MYSQL_DB, Username: $MYSQL_USER"

# Ensure all required packages are installed
echo "Installing dependencies..."
apt-get update && apt-get install -y build-essential libcairo2-dev libjpeg-turbo8-dev libpng-dev libtool-bin libossp-uuid-dev \
  freerdp2-dev libpango1.0-dev libssh2-1-dev libvncserver-dev libpulse-dev libssl-dev libvorbis-dev libwebp-dev tomcat9 tomcat9-admin \
  mysql-client wget || { echo "Dependency installation failed"; exit 1; }

# Install Guacamole Server
echo "Downloading and installing Guacamole server..."
wget -q https://downloads.apache.org/guacamole/1.5.5/source/guacamole-server-1.5.5.tar.gz -O guacamole-server.tar.gz
tar -xzf guacamole-server.tar.gz
cd guacamole-server-1.5.5 || exit 1
./configure --with-init-dir=/etc/init.d && make && make install && ldconfig && systemctl enable guacd && systemctl start guacd || { echo "Guacamole server installation failed"; exit 1; }
cd .. && rm -rf guacamole-server*

# Configure Guacamole Properties
echo "Configuring Guacamole properties..."
mkdir -p /etc/guacamole
cat << EOG > /etc/guacamole/guacamole.properties
mysql-hostname: $MYSQL_HOST
mysql-port: 3306
mysql-database: $MYSQL_DB
mysql-username: $MYSQL_USER
mysql-password: $MYSQL_PASSWORD
EOG

# Link guacamole.properties for Tomcat
ln -sf /etc/guacamole/guacamole.properties /usr/share/tomcat9/.guacamole

# Install MySQL Connector and Apply Schema
echo "Setting up MySQL Connector and applying schema..."
wget -q https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-8.0.33.tar.gz -O mysql-connector.tar.gz
tar -xzf mysql-connector.tar.gz && mv mysql-connector-java-8.0.33/mysql-connector-java-8.0.33.jar /usr/share/tomcat9/lib/
rm -rf mysql-connector*

wget -q https://downloads.apache.org/guacamole/1.5.5/binary/guacamole-auth-jdbc-1.5.5.tar.gz -O guacamole-auth-jdbc.tar.gz
tar -xzf guacamole-auth-jdbc.tar.gz
cat guacamole-auth-jdbc-1.5.5/mysql/schema/*.sql | mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DB" || { echo "MySQL schema setup failed"; exit 1; }

# Set the initial guacadmin password
echo "Setting initial password for guacadmin..."
mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DB" <<EOF
UPDATE guacamole_user SET password_hash=UNHEX(SHA2('$GUACADMIN_PASSWORD', 256)) WHERE username='guacadmin';
EOF || { echo "Failed to set guacadmin password"; exit 1; }

# Restart Tomcat
echo "Restarting Tomcat service..."
systemctl restart tomcat9 || { echo "Failed to restart Tomcat"; exit 1; }

echo "Guacamole installation completed successfully."
echo "Username: guacadmin"
echo "Password: $GUACADMIN_PASSWORD"
