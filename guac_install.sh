cat << 'EOF' > guac_install.sh
#!/bin/bash
LOG_FILE="/var/log/guac_deployment.log"
exec > >(tee -a $LOG_FILE) 2>&1

# Variables
MYSQL_HOST="$1"
MYSQL_USER="$2"
MYSQL_PASSWORD="$3"
MYSQL_DB="$4"
GUACADMIN_PASSWORD="$5"

# Install required packages
apt-get update && apt-get install -y build-essential libcairo2-dev libjpeg-turbo8-dev libpng-dev libtool-bin libossp-uuid-dev \
  freerdp2-dev libpango1.0-dev libssh2-1-dev libvncserver-dev libpulse-dev libssl-dev libvorbis-dev libwebp-dev tomcat9 tomcat9-admin \
  mysql-client wget

# Install Guacamole Server
wget https://downloads.apache.org/guacamole/1.5.5/source/guacamole-server-1.5.5.tar.gz
tar -xzf guacamole-server-1.5.5.tar.gz
cd guacamole-server-1.5.5
./configure --with-init-dir=/etc/init.d
make
make install
ldconfig
systemctl enable guacd
systemctl start guacd
cd ..

# Configure Guacamole Properties
mkdir -p /etc/guacamole
cat << EOG > /etc/guacamole/guacamole.properties
mysql-hostname: $MYSQL_HOST
mysql-port: 3306
mysql-database: $MYSQL_DB
mysql-username: $MYSQL_USER
mysql-password: $MYSQL_PASSWORD
EOG

# Link guacamole.properties for Tomcat
ln -s /etc/guacamole/guacamole.properties /usr/share/tomcat9/.guacamole

# Install MySQL Connector and Apply Schema
wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-8.0.33.tar.gz
tar -xzf mysql-connector-java-8.0.33.tar.gz
mv mysql-connector-java-8.0.33/mysql-connector-java-8.0.33.jar /usr/share/tomcat9/lib/
wget https://downloads.apache.org/guacamole/1.5.5/binary/guacamole-auth-jdbc-1.5.5.tar.gz
tar -xzf guacamole-auth-jdbc-1.5.5.tar.gz
cat guacamole-auth-jdbc-1.5.5/mysql/schema/*.sql | mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DB"

# Set the initial guacadmin password
mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DB" <<EOF
UPDATE guacamole_user SET password_hash=UNHEX(SHA2('$GUACADMIN_PASSWORD', 256)) WHERE username='guacadmin';
EOF

# Restart Tomcat
systemctl restart tomcat9
EOF

chmod +x guac_install.sh
