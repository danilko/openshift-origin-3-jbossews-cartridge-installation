#!/bin/bash

BROKER_OPENSHIFT_HOSTNAME=`hostname`
APP_OPENSHIFT_HOSTNAME=`echo ${BROKER_OPENSHIFT_HOSTNAME} | cut -d '.' -f2-`

# Make eth0 adapater enable during system start up
sed -i 's^ONBOOT=no^ONBOOT=yes^g' /etc/sysconfig/network-scripts/ifcfg-eth0

# Restart network service
service network restart

# Make current hostname to be resolvable
echo  -e "\n127.0.0.1 broker.platform.local" >> /etc/hosts

yum -y install java-1.7.0-openjdk-devel wget

cd /tmp
wget http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
rpm -Uvh epel-release-6*.rpm;
cat > /etc/yum.repos.d/openshift-origin-deps.repo <<"EOF"
[openshift-origin-deps]
name=OpenShift Origin Dependencies - EL6
baseurl=http://mirror.openshift.com/pub/origin-server/release/3/rhel-6/dependencies/$basearch/
gpgcheck=0
EOF

yum install -y ruby193-ruby unzip curl bind httpd-tools puppet augeas

# Install default config file
cat > ~/.openshift/oo-install-cfg.yml <<"EOF"
---
Version: 0.0.1
Description: This is the configuration file for the OpenShift Installer.
Deployment:
  DNS:
    component_domain: broker.platform.local
    register_components: Y
    app_domain: platform.local
  Hosts:
  - ip_addr: 127.0.0.1
    named_ip_addr: 127.0.0.1
    user: root
    host: broker.platform.local
    state: new
    ip_interface: eth0
    roles:
    - msgserver
    - dbserver
    - broker
    - node
    ssh_host: localhost
Vendor: OpenShift Origin Community
Subscription:
  type: yum
  jenkins_repo_base: http://pkg.jenkins-ci.org/redhat
  repos_base: https://mirror.openshift.com/pub/origin-server/release/3/rhel-6
Name: OpenShift Installer Configuration
EOF

sh <(curl -s https://install.openshift.com/) -w origin_deploy

# Update the DNS of current host
nsupdate -k /var/named/Kplatform.local*.key
server ${BROKER_OPENSHIFT_HOSTNAME}
update delete ${BROKER_OPENSHIFT_HOSTNAME} A
update add  180 A 127.0.0.1
send
quit

######################################
## SSL Cert Generation
######################################

mkdir -p /tmp/pki
cd /tmp/pki

cat >  platform.crt.config <<"EOF"
 RANDFILE               = $ENV::HOME/.rnd

 [ req ]
 default_bits           = 1024
 default_keyfile        = keyfile.pem
 distinguished_name     = req_distinguished_name
 attributes             = req_attributes
 prompt                 = no
 output_password        = changeme

 [ req_distinguished_name ]
 C                      = US
 ST                     = CA
 L                      = SAN JOSE
 O                      = PLATFORM
 OU                     = PLATFORM
 CN                     = *.platform.local
 emailAddress           = changeme

 [ req_attributes ]
 challengePassword              = changeme
EOF

# Generate a new key that lasts 365 days
openssl req -batch -x509 -nodes -days 365 -newkey rsa:2048 -keyout platform.key -out platform.crt -config platform.crt.config

# Backup old certificate and key
\cp -rf  /etc/pki/tls/certs/localhost.crt /etc/pki/tls/certs/localhost.crt.bak
\cp -rf  /etc/pki/tls/private/localhost.key /etc/pki/tls/private/localhost.key.bak

# Copy certificate and key
\cp -rf platform.crt /etc/pki/tls/certs/localhost.crt
\cp -rf platform.key /etc/pki/tls/private/localhost.key

# Setup so the serveralias also contain *platform.local
sed -i 's^ServerAlias localhost^ServerAlias localhost *.platform.local^g' /etc/httpd/conf.d/000001_openshift_origin_node.conf
sed -i 's^ServerAlias localhost^ServerAlias localhost *.platform.local^g' /etc/httpd/conf.d/000002_openshift_origin_broker_proxy.conf

# Get certificate through opnenssl
# Do not need since the cert is auto generated
#echo -n | openssl s_client -connect broker.platform.local:443 | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > platform.crt

# Import to java keystore to prevent ssl problem
keytool -import -trustcacerts -keystore /usr/lib/jvm/java-1.7.0-openjdk-1.7.*.x86_64/jre/lib/security/cacerts -storepass changeit -noprompt -alias platform_cert -file /tmp/pki/platform.crt

cd  /tmp
rm -rf /tmp/pki

# Restart httpd
service httpd restart

# Ensure cgconfig and cgred is on to make sure gear config
/sbin/chkconfig cgconfig on
/sbin/chkconfig cgred on

reboot now