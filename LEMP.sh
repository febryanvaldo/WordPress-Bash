#!/bin/bash

clear
echo "Install WordPress dengan LEMP di Ubuntu 22.04 LTS"
echo "----------------------"
echo "Spesifikasi:"
echo "1. Nginx"
echo "2. PHP 7.4, 8.0, 8.1, 8.2, 8.3"
echo "3. MariaDB 10.6"
echo "4. SSL Let's Encrypt"
echo "5. WordPress terbaru"
echo "----------------------"

ip=$(wget -qO- http://ipecho.net/plain | xargs echo)

echo "Informasi Domain dan WordPress"
echo "----------------------"
read -p "Domain(1) atau Subdomain(2) [1/2] = " tipedomain
read -p "Nama domain = " domain
read -p "Versi PHP [7.4/8.0/8.1/8.2/8.3] = " vphp
read -p "Email notifikasi SSL = " emailssl
read -p "Judul website = " wptitle
read -p "Username admin = " wpadmin
read -p "Email admin = " wpemail
echo "----------------------"

echo "Memulai instalasi dan konfigurasi ..."
echo "----------------------"
echo "Set TimeZone Asia/Jakarta"
timedatectl set-timezone Asia/Jakarta
echo

echo "Update & Upgrade"
apt update -y
apt upgrade -y
apt install pwgen -y
echo

echo "Tambah repository Nginx PPA"
add-apt-repository ppa:ondrej/nginx -y
echo

echo "Install Nginx"
apt install nginx -y
echo

echo "Tambah repository PHP PPA"
add-apt-repository ppa:ondrej/php -y
echo

echo "Install PHP $vphp"
apt install php$vphp php$vphp-fpm php$vphp-common php$vphp-cli php$vphp-mbstring php$vphp-gd php$vphp-intl php$vphp-xml php$vphp-mysql php$vphp-zip -y
echo

sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 200M/g" /etc/php/$vphp/fpm/php.ini
sed -i "s/post_max_size = 8M/post_max_size = 200M/g" /etc/php/$vphp/fpm/php.ini
sed -i "s/max_execution_time = 30/max_execution_time = 600/g" /etc/php/$vphp/fpm/php.ini
sed -i "s/max_input_time = 60/max_input_time = 600/g" /etc/php/$vphp/fpm/php.ini
sed -i "s/memory_limit = 128M/memory_limit = 256M/g" /etc/php/$vphp/fpm/php.ini

systemctl restart php$vphp-fpm

echo "Membuat document root"
mkdir /var/www/${domain}
echo "<?php phpinfo(); ?>" > /var/www/${domain}/index.php
echo

echo "Membuat konfigurasi server block ${domain}"
if [ $tipedomain == 1  ]
then
cat > /etc/nginx/conf.d/${domain}.conf << EOF
server {
    listen 80;
    server_name ${domain} www.${domain};
    root /var/www/${domain};
    index index.php index.html index.htm;

    location / {
      try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
      try_files \$fastcgi_script_name =404;
      include fastcgi_params;
      fastcgi_pass    unix:/run/php/php$vphp-fpm.sock;
      fastcgi_index   index.php;
      fastcgi_param DOCUMENT_ROOT   \$realpath_root;
      fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name; 
    }

    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
}
EOF
else
cat > /etc/nginx/conf.d/${domain}.conf << EOF
server {
    listen 80;
    server_name ${domain};
    root /var/www/${domain};
    index index.php index.html index.htm;

    location / {
      try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
      try_files \$fastcgi_script_name =404;
      include fastcgi_params;
      fastcgi_pass    unix:/run/php/php$vphp-fpm.sock;
      fastcgi_index   index.php;
      fastcgi_param DOCUMENT_ROOT   \$realpath_root;
      fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name; 
    }

    access_log /var/log/nginx/${domain}_access.log;
    error_log /var/log/nginx/${domain}_error.log;
}
EOF
fi
echo

echo "Restart Nginx"
systemctl enable nginx
systemctl restart nginx
echo

echo "Install Certbot Let's Encrypt"
apt install certbot python3-certbot-nginx -y
echo

echo "Request SSL untuk ${domain}"
if [ $tipedomain == 1  ]
then
certbot --non-interactive -m ${emailssl} --agree-tos --no-eff-email --nginx -d ${domain} -d www.${domain} --redirect
else
certbot --non-interactive -m ${emailssl} --agree-tos --no-eff-email --nginx -d ${domain} --redirect
fi
echo

echo "Install MariaDB"
apt install mariadb-server -y

echo "Membuat User & Database"
dbname="db_${domain//./}"
dbuser="usr_${domain//./}"
dbpass=$(pwgen 20 1)
mysql << EOF
CREATE DATABASE ${dbname};
CREATE USER '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}';
GRANT ALL PRIVILEGES ON ${dbname}.* TO '${dbuser}'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "Install WP-CLI"
wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

echo "Install WordPress"
wppass=$(pwgen 20 1)
cd /var/www/${domain}
rm -f index.php
wp core download --allow-root
wp config create --dbname=${dbname} --dbuser=${dbuser} --dbpass=${dbpass} --dbhost=localhost --allow-root
wp core install --url=https://${domain} --title="${wptitle}" --admin_user="${wpadmin}" --admin_password=${wppass} --admin_email="${wpemail}" --allow-root
chown -R www-data:www-data /var/www/${domain}
chmod -R 755 /var/www/${domain}
cd
echo

cat > /root/${domain}-conf.txt << EOF
IP Server = ${ip}
Domain = ${domain}
Email Let's Encrypt = ${emailssl}

Document Root = /var/www/${domain}
Server Block Conf = /etc/nginx/conf.d/${domain}.conf

Nama Database = ${dbname}
User Database = ${dbuser}
Password Database = ${dbpass}

WP Admin User = ${wpadmin}
WP Admin Email = ${wpemail}
WP Admin Password = ${wppass}
EOF

echo
echo "Instalasi WordPress dengan LEMP sudah selesai"
echo "Informasi konfigurasi tersimpan di /root/${domain}-conf.txt"
echo
cat /root/${domain}-conf.txt
echo "Reboot server ..."
reboot
