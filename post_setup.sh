#!/bin/bash

cd /tmp

TOMCAT7_VER=7.0.50
TOMCAT6_VER=6.0.37
MAVEN_VER=3.1.1

# Download binary
wget http://supergsego.com/apache/tomcat/tomcat-7/v${TOMCAT7_VER}/bin/apache-tomcat-${TOMCAT7_VER}.tar.gz
wget http://apache.mirrors.hoobly.com/tomcat/tomcat-6/v${TOMCAT6_VER}/bin/apache-tomcat-${TOMCAT6_VER}.tar.gz 
wget http://apache.petsads.us/maven/maven-3/3.1.1/binaries/apache-maven-${MAVEN_VER}-bin.tar.gz 
wget https://github.com/openshift/origin-server/archive/openshift-origin-release-3.zip 

# Untar/Unzip binaries
tar -xvf apache-tomcat-${TOMCAT7_VER}.tar.gz
tar -xvf apache-tomcat-${TOMCAT6_VER}.tar.gz
tar -xvf apache-maven-${MAVEN_VER}-bin.tar.gz
unzip openshift-origin-release-3.zip

######################################
## Install Maven
######################################
\cp -rf apache-maven-${MAVEN_VER} /etc/alternatives/maven

# Setup maven path system wide
echo -e 'export M2_HOME=/etc/alternatives/maven\nexport PATH=${M2_HOME}/bin:${PATH}'  > /etc/profile.d/maven.sh

source /etc/profile.d/maven.sh

mvn -v

######################################
## Install JBossews
######################################
# Copy jbossews/tomcat to correct location
\cp -rf apache-tomcat-${TOMCAT6_VER} /etc/alternatives/jbossews-1.0
\cp -rf apache-tomcat-${TOMCAT7_VER} /etc/alternatives/jbossews-2.0

# Copy openshift cartridges
\cp -rf origin-server-openshift-origin-release-3/cartridges/openshift-origin-cartridge-jbossews /usr/libexec/openshift/cartridges/jbossews

chmod a+x /usr/libexec/openshift/cartridges/jbossews/bin/*

# Install the cartridge
oo-admin-cartridge -a install -s /usr/libexec/openshift/cartridges/jbossews

# Clear broker cache
oo-admin-broker-cache -c

# Clean up folder
rm -rf origin-server-openshift-origin-release-3
rm -rf apache-maven-${MAVEN_VER}
rm -rf  apache-tomcat-${TOMCAT7_VER}
rm -rf  apache-tomcat-${TOMCAT6_VER}

######################################
## Change Default User Gear Size all to medium
######################################

# Resource limit file
RESOURCE_LIMIT_CONFIG_FILE=/etc/openshift/resource_limits.conf
sed -i 's^node_profile=small^node_profile=medium^g' ${RESOURCE_LIMIT_CONFIG_FILE}
sed -i 's^quota_blocks=1048576^quota_blocks=2097152^g' ${RESOURCE_LIMIT_CONFIG_FILE}
sed -i 's^quota_files=80000^quota_files=999999^g' ${RESOURCE_LIMIT_CONFIG_FILE}
sed -i 's^memory_limit_in_bytes=536870912       # 512MB^memory_limit_in_bytes=1073741824       # 1024MB^g' ${RESOURCE_LIMIT_CONFIG_FILE}
sed -i 's^memory_memsw_limit_in_bytes=641728512 # 512M + 100M (100M swap)^memory_memsw_limit_in_bytes=1178599424 # 1024M + 100M (100M swap)^g' ${RESOURCE_LIMIT_CONFIG_FILE}

sed -i 's^# limits_nofile=unlimited^limits_nofile=unlimited^g' ${RESOURCE_LIMIT_CONFIG_FILE}

# Reboot node services
service mcollective restart
oo-cgroup-enable --with-all-containers
oo-pam-enable --with-all-containers
oo-admin-ctl-tc restart

sed -i 's^"small"^"medium"^g' /etc/openshift/broker.conf

# Change demo user gear size
oo-admin-ctl-user --removegearsize small -l demo
oo-admin-ctl-user --addgearsize medium -l demo

# Clear broker cache
oo-admin-broker-cache -c

######################################
## Setup rhc tool
######################################

# Setup rhc tool
gem install rhc
echo yes | rhc setup --server=broker.platform.local -l demo -p changeme -k –no-create-token