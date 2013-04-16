#!/usr/bin/env bash
#
# OpenStack Grizzly Install Script
#
# allright reserved by Tomokazu Hirai @jedipunkz
#
# --------------------------------------------------------------------------------------
# Usage : sudo ./deploy.sh <node_type> <network_type>
#   node_type    : allinone | controller | network | compute | create_network
#   network_type : nova-network | quantum
# --------------------------------------------------------------------------------------

set -ex

# --------------------------------------------------------------------------------------
# create network via nova-network
# --------------------------------------------------------------------------------------
function create_network_nova-network() {
    check_para ${FIXED_RANGE}
    check_para ${FLOATING_RANGE}
    nova-manage network create private --fixed_range_v4=${FIXED_RANGE} --num_networks=1 --bridge=br100 --bridge_interface=eth0 --network_size=${NETWORK_SIZE} --dns1=8.8.8.8 --dns2=8.8.4.4 --multi_host=T
    nova-manage floating create --ip_range=${FLOATING_RANGE}
}

# --------------------------------------------------------------------------------------
# install nova for controller node with nova-network
# --------------------------------------------------------------------------------------
function controller_nova_setup_nova-network() {
    # install nova packages
    install_package nova-api nova-cert novnc nova-consoleauth nova-scheduler nova-novncproxy nova-doc nova-conductor
    #install_package nova-api nova-cert nova-common novnc nova-compute-kvm nova-consoleauth nova-scheduler nova-novncproxy rabbitmq-server vlan bridge-utils nova-network nova-console websockify novnc

    # create database for nova
    mysql -u root -p${MYSQL_PASS} -e "CREATE DATABASE nova;"
    mysql -u root -p${MYSQL_PASS} -e "GRANT ALL ON nova.* TO 'novaUser'@'%' IDENTIFIED BY 'novaPass';"
    
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.nova/api-paste.ini > /etc/nova/api-paste.ini
    sed -e "s#<CONTROLLER_IP>#${CONTROLLER_IP}#" -e "s#<VNC_IP>#${CONTROLLER_PUB_IP}#" -e "s#<DB_IP>#${DB_IP}#" -e "s#<DB_NOVA_USER>#${DB_NOVA_USER}#" -e "s#<DB_NOVA_PASS>#${DB_NOVA_PASS}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.nova/nova.conf > /etc/nova/nova.conf

    # synchronize database for nova
    nova-manage db sync

    # restart all services of nova
    cd /etc/init.d/; for i in $( ls nova-* ); do sudo service $i restart; done
    nova-manage service list
}

# --------------------------------------------------------------------------------------
# install nova for compute node with nova-network
# --------------------------------------------------------------------------------------
function compute_nova_setup_nova-network() {
    # install packages
    install_package nova-compute nova-network nova-api-metadata
    # erase dusts
    #virsh net-destroy default
    virsh net-undefine default
    restart_service libvirt-bin

    # deploy configuration for nova
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" $BASE_DIR/conf/etc.nova/api-paste.ini > /etc/nova/api-paste.ini
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<NOVA_IP>#${NOVA_IP}#" -e "s#<GLANCE_IP>#${GLANCE_IP}#" -e "s#<QUANTUM_IP>#${QUANTUM_IP}#" -e "s#<DB_IP>#${DB_IP}#" -e "s#<COMPUTE_NODE_IP>#${COMPUTE_NODE_IP}#" -e "s#<FIXED_RANGE>#${FIXED_RANGE}#" -e "s#<FIXED_START_ADDR>#${FIXED_START_ADDR}#" -e "s#<NETWORK_SIZE>#${NETWORK_SIZE}#" $BASE_DIR/conf/etc.nova/nova.conf.nova-network > /etc/nova/nova.conf
    
    chown -R nova. /etc/nova
    chmod 644 /etc/nova/nova.conf
    #nova-manage db sync

    # restart all services of nova
    cd /etc/init.d/; for i in $( ls nova-* ); do sudo service $i restart; done
    nova-manage service list
}

