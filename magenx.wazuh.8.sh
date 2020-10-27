#!/bin/bash
#=================================================================================#
#        MagenX Wazuh stack installation                                          #
#        Copyright (C) 2013-2020 admin@magenx.com                                 #
#        All rights reserved.                                                     #
#=================================================================================#
SELF=$(basename $0)
MAGENX_VER="1.8.313.2"
MAGENX_BASE="https://magenx.sh?wazuh"

# Config path
MAGENX_CONFIG_PATH="/opt/magenx/config"
mkdir -p ${MAGENX_CONFIG_PATH}

# CentOS version lock
CENTOS_VERSION="8"

# ELK version lock
ELKVER="7.9.1"
KAPPVER="3.13.2"
ELKREPO="7.x"

# Nginx extra configuration
NGINX_VERSION=$(curl -s http://nginx.org/en/download.html | grep -oP '(?<=gz">nginx-).*?(?=</a>)' | head -1)
NGINX_BASE="https://raw.githubusercontent.com/magenx/Magento-nginx-config/master/"	
GITHUB_REPO_API_URL="https://api.github.com/repos/magenx/Magento-nginx-config/contents/magento2"

EXTRA_PACKAGES="net-tools unzip vim wget curl sudo GeoIP GeoIP-devel geoipupdate openssl-devel mod_ssl dnf-automatic"

###################################################################################
###                                    COLORS                                   ###
###################################################################################

RED="\e[31;40m"
GREEN="\e[32;40m"
YELLOW="\e[33;40m"
WHITE="\e[37;40m"
BLUE="\e[0;34m"
### Background
DGREYBG="\t\t\e[100m"
BLUEBG="\e[1;44m"
REDBG="\t\t\e[41m"
### Styles
BOLD="\e[1m"
### Reset
RESET="\e[0m"

###################################################################################
###                            ECHO MESSAGES DESIGN                             ###
###################################################################################

function WHITETXT() {
        MESSAGE=${@:-"${RESET}Error: No message passed"}
        echo -e "\t\t${WHITE}${MESSAGE}${RESET}"
}
function BLUETXT() {
        MESSAGE=${@:-"${RESET}Error: No message passed"}
        echo -e "\t\t${BLUE}${MESSAGE}${RESET}"
}
function REDTXT() {
        MESSAGE=${@:-"${RESET}Error: No message passed"}
        echo -e "\t\t${RED}${MESSAGE}${RESET}"
}
function GREENTXT() {
        MESSAGE=${@:-"${RESET}Error: No message passed"}
        echo -e "\t\t${GREEN}${MESSAGE}${RESET}"
}
function YELLOWTXT() {
        MESSAGE=${@:-"${RESET}Error: No message passed"}
        echo -e "\t\t${YELLOW}${MESSAGE}${RESET}"
}
function BLUEBG() {
        MESSAGE=${@:-"${RESET}Error: No message passed"}
        echo -e "${BLUEBG}${MESSAGE}${RESET}"
}

###################################################################################
###                                  SYSTEM UPGRADE                             ###
###################################################################################

if ! grep -q "yes" ${MAGENX_CONFIG_PATH}/sysupdate >/dev/null 2>&1 ; then
## install all extra packages
echo
BLUEBG "[~]    SYSTEM UPDATE AND PACKAGES INSTALLATION   [~]"
WHITETXT "-------------------------------------------------------------------------------------"
echo
dnf install -y dnf-utils >/dev/null 2>&1
dnf config-manager --set-enabled PowerTools >/dev/null 2>&1
dnf -y install ${EXTRA_PACKAGES}
## disable some module
dnf -y module disable nginx php redis varnish >/dev/null 2>&1
dnf -y upgrade --nobest
echo
echo "yes" > ${MAGENX_CONFIG_PATH}/sysupdate
echo
fi
echo
echo


###################################################################################
###                         WAZUH + ELK STACK INSTALLATION                      ###
###################################################################################


WHITETXT "============================================================================="
echo
GREENTXT "WAZUH 3 + ELK ${ELKVER} STACK INSTALLATION:"
echo
GREENTXT "Nginx installation:"
cat > /etc/yum.repos.d/nginx.repo <<END
[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
END

dnf -y install nginx
echo

GREENTXT "JAVA installation:"	
dnf -y install java
echo
GREENTXT "Elasticsearch installation:"
echo
rpm --import https://packages.elastic.co/GPG-KEY-elasticsearch
cat > /etc/yum.repos.d/elastic.repo <<EOF
[elasticsearch-${ELKREPO}]
name=Elasticsearch repository for ${ELKREPO} packages
baseurl=https://artifacts.elastic.co/packages/${ELKREPO}/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=0
autorefresh=1
type=rpm-md
EOF
echo
dnf -y install --enablerepo=elasticsearch-${ELKREPO} elasticsearch-${ELKVER}
echo
echo "discovery.type: single-node" >> /etc/elasticsearch/elasticsearch.yml
echo "xpack.security.enabled: true" >> /etc/elasticsearch/elasticsearch.yml
sed -i "s/.*cluster.name.*/cluster.name: wazuh/" /etc/elasticsearch/elasticsearch.yml
sed -i "s/.*node.name.*/node.name: wazuh-node1/" /etc/elasticsearch/elasticsearch.yml
sed -i "s/.*network.host.*/network.host: 127.0.0.1/" /etc/elasticsearch/elasticsearch.yml
sed -i "s/.*http.port.*/http.port: 9200/" /etc/elasticsearch/elasticsearch.yml
sed -i "s/-Xms.*/-Xms512m/" /etc/elasticsearch/jvm.options
sed -i "s/-Xmx.*/-Xmx512m/" /etc/elasticsearch/jvm.options
chown -R :elasticsearch /etc/elasticsearch/*
systemctl daemon-reload
systemctl enable elasticsearch.service
systemctl restart elasticsearch.service

/usr/share/elasticsearch/bin/elasticsearch-setup-passwords auto -b > /tmp/elasticsearch

cat > ${MAGENX_CONFIG_PATH}/elasticsearch <<END
APM_SYSTEM_PASSWORD="$(awk '/PASSWORD apm_system/ { print $4 }' /tmp/elasticsearch)"
KIBANA_SYSTEM_PASSWORD="$(awk '/PASSWORD kibana_system/ { print $4 }' /tmp/elasticsearch)"
KIBANA_PASSWORD="$(awk '/PASSWORD kibana =/ { print $4 }' /tmp/elasticsearch)"
LOGSTASH_SYSTEM_PASSWORD="$(awk '/PASSWORD logstash_system/ { print $4 }' /tmp/elasticsearch)"
BEATS_SYSTEM_PASSWORD="$(awk '/PASSWORD beats_system/ { print $4 }' /tmp/elasticsearch)"
REMOTE_MONITORING_USER_PASSWORD="$(awk '/PASSWORD remote_monitoring_user/ { print $4 }' /tmp/elasticsearch)"
ELASTIC_PASSWORD="$(awk '/PASSWORD elastic/ { print $4 }' /tmp/elasticsearch)"
END

echo
GREENTXT "WAZUH MANAGER INSTALLATION"
cat > /etc/yum.repos.d/wazuh.repo <<EOF
[wazuh_repo]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=0
name=Wazuh repository
baseurl=https://packages.wazuh.com/3.x/yum/
protect=1
EOF
yum -y install wazuh-manager-${KAPPVER}
echo
GREENTXT "WAZUH API + NODEJS INSTALLATION"
curl --location https://rpm.nodesource.com/setup_10.x | bash
yum -y install nodejs
yum -y --enablerepo=wazuh_repo install wazuh-api-${KAPPVER}
echo
GREENTXT "PACKETBEAT INSTALLATION:"
yum -y install --enablerepo=elasticsearch-${ELKREPO} packetbeat-${ELKVER}
systemctl daemon-reload
systemctl enable packetbeat.service
systemctl start packetbeat.service
echo
GREENTXT "FILEBEAT INSTALLATION:"
yum -y install --enablerepo=elasticsearch-${ELKREPO} filebeat-${ELKVER}
curl -o /etc/filebeat/filebeat.yml https://raw.githubusercontent.com/wazuh/wazuh/v${KAPPVER}/extensions/filebeat/7.x/filebeat.yml
chmod go+r /etc/filebeat/filebeat.yml
curl -o /etc/filebeat/wazuh-template.json https://raw.githubusercontent.com/wazuh/wazuh/v${KAPPVER}/extensions/elasticsearch/7.x/wazuh-template.json
chmod go+r /etc/filebeat/wazuh-template.json
sed -i "s/YOUR_ELASTIC_SERVER_IP/127.0.0.1/" /etc/filebeat/filebeat.yml
sed -i "s/#pipeline: geoip/pipeline: geoip/" /etc/filebeat/filebeat.yml
curl https://raw.githubusercontent.com/magenx/WAZUH-OSSEC/master/elkgeoip.json | curl -X PUT "localhost:9200/_ingest/pipeline/geoip" -H 'Content-Type: application/json' -d @-
systemctl daemon-reload
systemctl enable filebeat.service
systemctl start filebeat.service
echo
GREENTXT "LOGSTASH INSTALLATION:"
yum -y install --enablerepo=elasticsearch-${ELKREPO} logstash-${ELKVER}
curl -o /etc/logstash/conf.d/01-wazuh.conf https://raw.githubusercontent.com/wazuh/wazuh/v${KAPPVER}/extensions/logstash/${ELKREPO}/01-wazuh-remote.conf
sed -i "s/YOUR_ELASTIC_SERVER_IP/127.0.0.1/" /etc/logstash/conf.d/01-wazuh.conf
usermod -a -G ossec logstash
systemctl daemon-reload
systemctl enable logstash.service
systemctl start logstash.service
echo
echo
GREENTXT "KIBANA INSTALLATION:"
yum -y install --enablerepo=elasticsearch-${ELKREPO} kibana-${ELKVER}
cd /usr/share/kibana/
su kibana bin/kibana-plugin install  https://packages.wazuh.com/wazuhapp/wazuhapp-${KAPPVER}_${ELKVER}.zip
echo
systemctl daemon-reload
systemctl enable kibana.service
systemctl restart kibana.service
echo
echo
yum-config-manager --disable elasticsearch-${ELKREPO}
yum-config-manager --disable wazuh_repo
echo
GREENTXT "OSSEC WAZUH API SETTINGS"
sed -i 's/.*config.host.*/config.host = "127.0.0.1";/' /var/ossec/api/configuration/config.js
echo
read -e -p "---> Enter domain name: " -i "wazuh.example.com" WAZUH_DOMAIN
KIBANA_PORT=$(shuf -i 10322-10539 -n 1)
KIBANA_PASSWORD=$(head -c 500 /dev/urandom | tr -dc 'a-zA-Z0-9!@#$%^&?=+_[]{}()<>-' | fold -w 6 | head -n 1)
WAZUH_API_PASSWORD=$(head -c 500 /dev/urandom | tr -dc 'a-zA-Z0-9!@#$%^&?=+_[]{}()<>-' | fold -w 6 | head -n 1)
htpasswd -b -c /etc/nginx/.wazuh wazuh-web "${KIBANA_PASSWORD}"
cd /var/ossec/api/configuration/auth
htpasswd -b -c user wazuh-api "${WAZUH_API_PASSWORD}"
systemctl restart wazuh-api
echo
GREENTXT "LETSENCRYPT SSL CERTIFICATE REQUEST"
read -e -p "---> Enter admin email: " -i "admin@domain.com" ADMIN_EMAIL
wget -q https://dl.eff.org/certbot-auto -O /usr/local/bin/certbot-auto
chmod +x /usr/local/bin/certbot-auto
certbot-auto --install-only
certbot-auto certonly --agree-tos --no-eff-email --email ${ADMIN_EMAIL} --webroot -w /tmp
systemctl reload nginx.service
echo
cat > /etc/nginx/sites-available/kibana.conf <<END
  ## certbot-auto renew webroot
  server {
    listen 80;
    server_name ${WAZUH_DOMAIN};

    location ~ /\.well-known/acme-challenge {
        root /tmp;
    }

    location / { return 301 https://${WAZUH_DOMAIN}$request_uri;  }
  }
 
 server {
  listen ${KIBANA_PORT} ssl http2;
  server_name           ${WAZUH_DOMAIN};
  access_log            /var/log/nginx/access.log;
  
  ## SSL CONFIGURATION
	#ssl_certificate     /etc/letsencrypt/live/${WAZUH_DOMAIN}/fullchain.pem; 
	#ssl_certificate_key /etc/letsencrypt/live/${WAZUH_DOMAIN}/privkey.pem;
	
    auth_basic  "blackhole";
    auth_basic_user_file .wazuh;
       
       location / {
               proxy_pass http://127.0.0.1:5601;
       }
}
END

echo

cd /etc/nginx/sites-enabled/
ln -s /etc/nginx/sites-available/kibana.conf kibana.conf
service nginx reload
echo
YELLOWTXT "KIBANA WEB INTERFACE PORT: ${KIBANA_PORT}"
YELLOWTXT "KIBANA HTTP AUTH: wazuh-web ${KIBANA_PASSWORD}"
echo
YELLOWTXT "WAZUH API AUTH: wazuh-api ${WAZUH_API_PASSWORD}"
echo
