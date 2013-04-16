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
# initialize
# --------------------------------------------------------------------------------------
function init() {
    # at first, update package repository cache
    apt-get update

    # install ntp
    install_package ntp
    cp $BASE_DIR/conf/etc.ntp.conf /etc/ntp.conf

    # install misc software
    apt-get install -y vlan bridge-utils rabbitmq-server

    # enable router
    #sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    #sysctl -p

    # use Ubuntu Cloud Archive repository
    apt-get install ubuntu-cloud-keyring
    echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/grizzly main >> /etc/apt/sources.list.d/grizzly.list
    apt-get update
}

# --------------------------------------------------------------------------------------
# set shell environment
# --------------------------------------------------------------------------------------
function shell_env() {

    # set environments for 'admin' user, this script will be operated with this user
    export OS_TENANT_NAME=${OS_TENANT_NAME}
    export OS_USERNAME=${OS_USERNAME}
    export OS_PASSWORD=${OS_PASSWORD}
    export SERVICE_TOKEN=${SERVICE_TOKEN}
    export OS_AUTH_URL="http://${KEYSTONE_IP}:5000/v2.0/"
    export SERVICE_ENDPOINT="http://${KEYSTONE_IP}:35357/v2.0"

    # create ~/openstackrc for 'admin' user
    echo "export OS_TENANT_NAME=${OS_TENANT_NAME}" > ~/openstackrc
    echo "export OS_USERNAME=${OS_USERNAME}" >> ~/openstackrc
    echo "export OS_PASSWORD=${OS_PASSWORD}" >> ~/openstackrc
    echo "export SERVICE_TOKEN=${SERVICE_TOKEN}" >> ~/openstackrc
    echo "export OS_AUTH_URL=\"http://${KEYSTONE_IP}:5000/v2.0/\"" >> ~/openstackrc
    if [[ "$1" = "allinone" ]]; then
        echo "export SERVICE_ENDPOINT=\"http://${KEYSTONE_IP}:35357/v2.0\"" >> ~/openstackrc
    elif [[ "$1" = "separate" ]]; then
        echo "export SERVICE_ENDPOINT=\"http://${CONTROLLER_NODE_PUB_IP}:35357/v2.0\"" >> ~/openstackrc
    else
        echo "mode must be allinone or separate."
        exit 1
    fi

    # create openstackrc for 'demo' user. this user is useful for horizon.
    echo "export OS_TENANT_NAME=service" > ~/openstackrc-demo
    echo "export OS_USERNAME=${DEMO_USER}" >> ~/openstackrc-demo
    echo "export OS_PASSWORD=${DEMO_PASSWORD}" >> ~/openstackrc-demo
    echo "export SERVICE_TOKEN=${SERVICE_TOKEN}" >> ~/openstackrc-demo
    echo "export OS_AUTH_URL=\"http://${KEYSTONE_IP}:5000/v2.0/\"" >> ~/openstackrc-demo
    if [[ "$1" = "allinone" ]]; then
        echo "export SERVICE_ENDPOINT=http://${KEYSTONE_IP}:35357/v2.0" >> ~/openstackrc-demo
    elif [[ "$1" = "separate" ]]; then
        echo "export SERVICE_ENDPOINT=http://${CONTROLLER_NODE_PUB_IP}:35357/v2.0" >> ~/openstackrc-demo
    else
        echo "mode must be allinone or separate."
        exit 1
    fi
}

# --------------------------------------------------------------------------------------
# install mysql
# --------------------------------------------------------------------------------------
function mysql_setup() {
    # set MySQL root user's password
    echo mysql-server-5.5 mysql-server/root_password password ${MYSQL_PASS} | debconf-set-selections
    echo mysql-server-5.5 mysql-server/root_password_again password ${MYSQL_PASS} | debconf-set-selections
    # install mysql
    install_package mysql-server python-mysqldb

    # enable to access to mysql via network
    sed -i -e 's/127.0.0.1/0.0.0.0/' /etc/mysql/my.cnf
    restart_service mysql
}

# --------------------------------------------------------------------------------------
# install keystone
# --------------------------------------------------------------------------------------
function keystone_setup() {
    # install keystone daemon and client software
    install_package keystone python-keystone python-keystoneclient

    # create database for keystone
    mysql -uroot -p${MYSQL_PASS} -e "CREATE DATABASE keystone;"
    mysql -uroot -p${MYSQL_PASS} -e "GRANT ALL ON keystone.* TO '${DB_KEYSTONE_USER}'@'%' IDENTIFIED BY '${DB_KEYSTONE_PASS}';"

    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<DB_KEYSTONE_USER>#${DB_KEYSTONE_USER}#" -e "s#<DB_KEYSTONE_PASS>#${DB_KEYSTONE_PASS}#" $BASE_DIR/conf/etc.keystone/keystone.conf > /etc/keystone/keystone.conf
    restart_service keystone
    keystone-manage db_sync
    
    # Creating Tenants
    TENANT_ID_ADMIN=$(keystone tenant-create --name admin | grep ' id ' | get_field 2)
    TENANT_ID_SERVICE=$(keystone tenant-create --name service | grep ' id ' | get_field 2)
    
    # Creating Users
    USER_ID_ADMIN=$(keystone user-create --name admin --pass ${ADMIN_PASSWORD} --tenant-id ${TENANT_ID_SERVICE} --email admin@example.com | grep ' id ' | get_field 2)
    USER_ID_NOVA=$(keystone user-create --name nova --pass ${SERVICE_PASSWORD} --tenant-id ${TENANT_ID_SERVICE} --email admin@example.com | grep ' id ' | get_field 2)
    USER_ID_GLANCE=$(keystone user-create --name glance --pass ${SERVICE_PASSWORD} --tenant-id ${TENANT_ID_SERVICE} --email admin@example.com | grep ' id ' | get_field 2)
    USER_ID_CINDER=$(keystone user-create --name cinder --pass ${SERVICE_PASSWORD} --tenant-id ${TENANT_ID_SERVICE} --email admin@example.com | grep ' id ' | get_field 2)
    USER_ID_DEMO=$(keystone user-create --name ${DEMO_USER} --pass ${DEMO_PASSWORD} --tenant-id ${TENANT_ID_SERVICE} --email demo@example.com | grep ' id ' | get_field 2)
    if [[ "$1" = "quantum" ]]; then
        USER_ID_QUANTUM=$(keystone user-create --name quantum --pass ${SERVICE_PASSWORD} --tenant-id ${TENANT_ID_SERVICE} --email admin@example.com | grep ' id ' | get_field 2)
    fi
    
    # Creating Roles
    ROLE_ID_ADMIN=$(keystone role-create --name admin | grep ' id ' | get_field 2)
    ROLE_ID_KEYSTONE_ADMIN=$(keystone role-create --name=KeystoneAdmin | grep ' id ' | get_field 2)
    ROLE_ID_KEYSTONE_SERVICE=$(keystone role-create --name=KeystoneService | grep ' id ' | get_field 2)
    ROLE_ID_MEMBER=$(keystone role-create --name Member | grep ' id ' | get_field 2)
    
    # To add a role of 'admin' to the user 'admin' of the tenant 'admin'.
    keystone user-role-add --user-id ${USER_ID_ADMIN} --role-id ${ROLE_ID_ADMIN} --tenant-id ${TENANT_ID_ADMIN}
    keystone user-role-add --user-id ${USER_ID_ADMIN} --role-id ${ROLE_ID_KEYSTONE_ADMIN} --tenant-id ${TENANT_ID_ADMIN}
    keystone user-role-add --user-id ${USER_ID_ADMIN} --role-id ${ROLE_ID_KEYSTONE_SERVICE} --tenant-id ${TENANT_ID_ADMIN}
    
    # The following commands will add a role of 'admin' to the users 'nova', 'glance' and 'swift' of the tenant 'service'.
    keystone user-role-add --user-id ${USER_ID_NOVA} --role-id ${ROLE_ID_ADMIN} --tenant-id ${TENANT_ID_SERVICE}
    keystone user-role-add --user-id ${USER_ID_GLANCE} --role-id ${ROLE_ID_ADMIN} --tenant-id ${TENANT_ID_SERVICE}
    keystone user-role-add --user-id ${USER_ID_CINDER} --role-id ${ROLE_ID_ADMIN} --tenant-id ${TENANT_ID_SERVICE}
    if [[ "$1" = "quantum" ]]; then
        keystone user-role-add --user-id ${USER_ID_QUANTUM} --role-id ${ROLE_ID_ADMIN} --tenant-id ${TENANT_ID_SERVICE}
    fi
    
    # The 'Member' role is used by Horizon and Swift. So add the 'Member' role accordingly.
    keystone user-role-add --user-id ${USER_ID_ADMIN} --role-id ${ROLE_ID_MEMBER} --tenant-id ${TENANT_ID_ADMIN}
    keystone user-role-add --user-id ${USER_ID_DEMO} --role-id ${ROLE_ID_MEMBER} --tenant-id ${TENANT_ID_SERVICE}
    
    # Creating Services
    SERVICE_ID_COMPUTE=$(keystone service-create --name nova --type compute --description 'OpenStack Compute Service' | grep ' id ' | get_field 2)
    SERVICE_ID_IMAGE=$(keystone service-create --name glance --type image --description 'OpenStack Image Service' | grep ' id ' | get_field 2)
    SERVICE_ID_VOLUME=$(keystone service-create --name cinder --type volume --description 'OpenStack Volume Service' | grep ' id ' | get_field 2)
    SERVICE_ID_IDENTITY=$(keystone service-create --name keystone --type identity --description 'OpenStack Identity Service' | grep ' id ' | get_field 2)
    SERVICE_ID_EC2=$(keystone service-create --name ec2 --type ec2 --description 'EC2 Service' | grep ' id ' | get_field 2)
    if [[ "$1" = "quantum" ]]; then
        SERVICE_ID_QUANTUM=$(keystone service-create --name quantum --type network --description 'OpenStack Networking Service' | grep ' id ' | get_field 2)
    fi
    
    keystone service-list
    
    # Creating Endpoints
    if [[ "$2" = "controller" ]]; then
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_EC2 --publicurl "http://${KEYSTONE_PUB_IP}:8773/services/Cloud" --adminurl "http://${KEYSTONE_IP}:8773/services/Admin" --internalurl "http://${KEYSTONE_IP}:8773/services/Cloud"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_IDENTITY --publicurl "http://${KEYSTONE_PUB_IP}:5000/v2.0" --adminurl "http://${KEYSTONE_IP}:35357/v2.0" --internalurl "http://${KEYSTONE_IP}:5000/v2.0"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_VOLUME --publicurl "http://${KEYSTONE_PUB_IP}:8776/v1/\$(tenant_id)s" --adminurl "http://${KEYSTONE_IP}:8776/v1/\$(tenant_id)s" --internalurl "http://${KEYSTONE_IP}:8776/v1/\$(tenant_id)s"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_IMAGE --publicurl "http://${KEYSTONE_PUB_IP}:9292/v2" --adminurl "http://${KEYSTONE_IP}:9292/v2" --internalurl "http://${KEYSTONE_IP}:9292/v2"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_COMPUTE --publicurl "http://${KEYSTONE_PUB_IP}:8774/v2/\$(tenant_id)s" --adminurl "http://${KEYSTONE_IP}:8774/v2/\$(tenant_id)s" --internalurl "http://${KEYSTONE_IP}:8774/v2/\$(tenant_id)s"
        if [[ "$1" = "quantum" ]]; then
            keystone endpoint-create --region myregion --service-id $SERVICE_ID_QUANTUM --publicurl "http://${KEYSTONE_PUB_IP}:9696/" --adminurl "http://${KEYSTONE_IP}:9696/" --internalurl "http://${KEYSTONE_IP}:9696/"
        fi
    else
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_EC2 --publicurl "http://${KEYSTONE_IP}:8773/services/Cloud" --adminurl "http://${KEYSTONE_IP}:8773/services/Admin" --internalurl "http://${KEYSTONE_IP}:8773/services/Cloud"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_IDENTITY --publicurl "http://${KEYSTONE_IP}:5000/v2.0" --adminurl "http://${KEYSTONE_IP}:35357/v2.0" --internalurl "http://${KEYSTONE_IP}:5000/v2.0"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_VOLUME --publicurl "http://${KEYSTONE_IP}:8776/v1/\$(tenant_id)s" --adminurl "http://${KEYSTONE_IP}:8776/v1/\$(tenant_id)s" --internalurl "http://${KEYSTONE_IP}:8776/v1/\$(tenant_id)s"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_IMAGE --publicurl "http://${KEYSTONE_IP}:9292/v2" --adminurl "http://${KEYSTONE_IP}:9292/v2" --internalurl "http://${KEYSTONE_IP}:9292/v2"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_COMPUTE --publicurl "http://${KEYSTONE_IP}:8774/v2/\$(tenant_id)s" --adminurl "http://${KEYSTONE_IP}:8774/v2/\$(tenant_id)s" --internalurl "http://${KEYSTONE_IP}:8774/v2/\$(tenant_id)s"
        if [[ "$1" = "quantum" ]]; then
            keystone endpoint-create --region myregion --service-id $SERVICE_ID_QUANTUM --publicurl "http://${KEYSTONE_IP}:9696/" --adminurl "http://${KEYSTONE_IP}:9696/" --internalurl "http://${KEYSTONE_IP}:9696/"
        fi
    fi
}

# --------------------------------------------------------------------------------------
# install glance
# --------------------------------------------------------------------------------------
function glance_setup() {
    # install packages
    install_package glance
    
    # create database for keystone service
    mysql -uroot -p${MYSQL_PASS} -e "CREATE DATABASE glance;"
    mysql -uroot -p${MYSQL_PASS} -e "GRANT ALL ON glance.* TO '${DB_GLANCE_USER}'@'%' IDENTIFIED BY '${DB_GLANCE_PASS}';"
    
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<DB_IP>#${DB_IP}#" -e "s#<DB_GLANCE_USER>#${DB_GLANCE_USER}#" -e "s#<DB_GLANCE_PASS>#${DB_GLANCE_PASS}#" $BASE_DIR/conf/etc.glance/glance-api.conf > /etc/glance/glance-api.conf
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<DB_IP>#${DB_IP}#" -e "s#<DB_GLANCE_USER>#${DB_GLANCE_USER}#" -e "s#<DB_GLANCE_PASS>#${DB_GLANCE_PASS}#" $BASE_DIR/conf/etc.glance/glance-registry.conf > /etc/glance/glance-registry.conf
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.glance/glance-registry-paste.ini > /etc/glance/glance-registry-paste.ini
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.glance/glance-api-paste.ini > /etc/glance/glance-api-paste.ini
    
    # restart process and syncing database
    restart_service glance-registry
    restart_service glance-api
    glance-manage db_sync
}

# --------------------------------------------------------------------------------------
# add os image
# --------------------------------------------------------------------------------------
function os_add () {
    # install cirros 0.3.0 x86_64 os image
    if [[ -f ./os.img ]]; then
        mv ./os.img ./os.img.bk
    fi
    wget ${OS_IMAGE_URL} -O ./os.img
    #glance add name="${OS_IMAGE_NAME}" is_public=true container_format=ovf disk_format=qcow2 < ./os.img
    glance image-create --name="${OS_IMAGE_NAME}" --is-public true --container-format bare --disk-format qcow2 < ./os.img
}

# --------------------------------------------------------------------------------------
# install nova for all in one with quantum
# --------------------------------------------------------------------------------------
function allinone_nova_setup() {
    install_package kvm libvirt-bin pm-utils
    restart_service dbus
    sleep 3
    #virsh net-destroy default
    virsh net-undefine default
    restart_service libvirt-bin
    
    install_package nova-api nova-cert novnc nova-consoleauth nova-scheduler nova-novncproxy nova-doc nova-conductor nova-compute-kvm
    mysql -u root -p${MYSQL_PASS} -e "CREATE DATABASE nova;"
    mysql -u root -p${MYSQL_PASS} -e "GRANT ALL ON nova.* TO '${DB_NOVA_USER}'@'%' IDENTIFIED BY '${DB_NOVA_PASS}';"
    
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.nova/api-paste.ini > /etc/nova/api-paste.ini
    sed -e "s#<CONTROLLER_IP>#${HOST_IP}#" -e "s#<VNC_IP>#${HOST_IP}#" -e "s#<DB_IP>#${DB_IP}#" -e "s#<DB_NOVA_USER>#${DB_NOVA_USER}#" -e "s#<DB_NOVA_PASS>#${DB_NOVA_PASS}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" -e "s#<LOCAL_IP>#${HOST_IP}#" $BASE_DIR/conf/etc.nova/nova.conf > /etc/nova/nova.conf
    cp $BASE_DIR/conf/etc.nova/nova-compute.conf /etc/nova/nova-compute.conf
    
    nova-manage db sync
    cd /etc/init.d/; for i in $( ls nova-* ); do sudo service $i restart; done
    nova-manage service list
}

# --------------------------------------------------------------------------------------
# install nova for controller node with quantum
# --------------------------------------------------------------------------------------
function controller_nova_setup() {
    # install packages
    #install_package nova-api nova-cert novnc nova-consoleauth nova-scheduler nova-novncproxy rabbitmq-server vlan bridge-utils
    install_package nova-api nova-cert novnc nova-consoleauth nova-scheduler nova-novncproxy nova-doc nova-conductor
    mysql -u root -p${MYSQL_PASS} -e "CREATE DATABASE nova;"
    mysql -u root -p${MYSQL_PASS} -e "GRANT ALL ON nova.* TO 'novaUser'@'%' IDENTIFIED BY 'novaPass';"
    
    # set configuration files for nova
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.nova/api-paste.ini > /etc/nova/api-paste.ini

    sed -e "s#<CONTROLLER_IP>#${CONTROLLER_NODE_IP}#" -e "s#<VNC_IP>#${CONTROLLER_NODE_PUB_IP}#" -e "s#<DB_IP>#${DB_IP}#" -e "s#<DB_NOVA_USER>#${DB_NOVA_USER}#" -e "s#<DB_NOVA_PASS>#${DB_NOVA_PASS}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" -e "s#<LOCAL_IP>#${CONTROLLER_NODE_IP}#" $BASE_DIR/conf/etc.nova/nova.conf > /etc/nova/nova.conf

    nova-manage db sync
    # restart processes
    cd /etc/init.d/; for i in $( ls nova-* ); do sudo service $i restart; done
    nova-manage service list
}

# --------------------------------------------------------------------------------------
# install additional nova for compute node with quantum
# --------------------------------------------------------------------------------------
function compute_nova_setup() {
    # install dependency packages
    install_package vlan bridge-utils kvm libvirt-bin pm-utils
    restart_service dbus
    sleep 3
    #virsh net-destroy default
    virsh net-undefine default

    # install openvswitch and add bridge interfaces
    install_package openvswitch-switch
    ovs-vsctl add-br br-int
    ovs-vsctl add-br br-eth1
    ovs-vsctl add-port br-eth1 ${DATA_NIC_COMPUTE}

    # install openvswitch quantum plugin
    install_package quantum-plugin-openvswitch-agent

    sed -e "s#<DB_IP>#${DB_IP}#" -e "s#<QUANTUM_IP>#${COMPUTE_NODE_IP}#" $BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini > /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini
    sed -e "s#<CONTROLLER_IP>#${CONTROLLER_NODE_IP}#" $BASE_DIR/conf/etc.quantum/quantum.conf > /etc/quantum/quantum.conf

    # quantum setup
    service quantum-plugin-openvswitch-agent restart

    # nova setup
    install_package nova-compute-kvm

    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.nova/api-paste.ini > /etc/nova/api-paste.ini
    sed -e "s#<CONTROLLER_IP>#${CONTROLLER_NODE_IP}#" -e "s#<VNC_IP>#${CONTROLLER_NODE_PUB_IP}#" -e "s#<DB_IP>#${DB_IP}#" -e "s#<DB_NOVA_USER>#${DB_NOVA_USER}#" -e "s#<DB_NOVA_PASS>#${DB_NOVA_PASS}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" -e "s#<LOCAL_IP>#${COMPUTE_NODE_IP}#" $BASE_DIR/conf/etc.nova/nova.conf > /etc/nova/nova.conf
    cp $BASE_DIR/conf/etc.nova/nova-compute.conf /etc/nova/nova-compute.conf

    #nova-manage db sync

    # restart processes
    cd /etc/init.d/; for i in $( ls nova-* ); do sudo service $i restart; done
    nova-manage service list
}

# --------------------------------------------------------------------------------------
# install cinder
# --------------------------------------------------------------------------------------
function cinder_setup() {
    # install packages
    install_package cinder-api cinder-scheduler cinder-volume iscsitarget open-iscsi iscsitarget-dkms
    sed -i 's/false/true/g' /etc/default/iscsitarget
    service iscsitarget start
    service open-iscsi start
    # create databases
    mysql -uroot -p${MYSQL_PASS} -e "CREATE DATABASE cinder;"
    mysql -uroot -p${MYSQL_PASS} -e "GRANT ALL ON cinder.* TO '${DB_CINDER_USER}'@'%' IDENTIFIED BY '${DB_CINDER_PASS}';"
    
    # set configuration files for cinder
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<CONTROLLER_PUB_IP>#${HOST_PUB_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.cinder/api-paste.ini > /etc/cinder/api-paste.ini
    sed -e "s#<DB_IP>#${DB_IP}#" -e "s#<DB_CINDER_USER>#${DB_CINDER_USER}#" -e "s#<DB_CINDER_PASS>#${DB_CINDER_PASS}#" $BASE_DIR/conf/etc.cinder/cinder.conf > /etc/cinder/cinder.conf
    
    cinder-manage db sync

    # create pyshical volume and volume group
    pvcreate ${CINDER_VOLUME}
    vgcreate cinder-volumes ${CINDER_VOLUME}

    # restart processes
    restart_service cinder-volume
    restart_service cinder-api
    restart_service cinder-scheduler
}

# --------------------------------------------------------------------------------------
# install horizon
# --------------------------------------------------------------------------------------
function horizon_setup() {
    install_package openstack-dashboard memcached
    cp $BASE_DIR/conf/etc.openstack-dashboard/local_settings.py /etc/openstack-dashboard/local_settings.py
    restart_service apache2
    restart_service memcached
}

# --------------------------------------------------------------------------------------
#  make seciruty group rule named 'default' to allow SSH and ICMP traffic
# --------------------------------------------------------------------------------------
function scgroup_allow() {
    # turn on demo user
    export SERVICE_TOKEN=${SERVICE_TOKEN}
    export OS_TENANT_NAME=service
    export OS_USERNAME=${DEMO_USER}
    export OS_PASSWORD=${DEMO_PASSWORD}
    export OS_AUTH_URL="http://${KEYSTONE_IP}:5000/v2.0/"
    export SERVICE_ENDPOINT="http://${KEYSTONE_IP}:35357/v2.0"

    nova --no-cache secgroup-add-rule default tcp 22 22 0.0.0.0/0
    nova --no-cache secgroup-add-rule default icmp -1 -1 0.0.0.0/0

    # turn back to admin user
    export SERVICE_TOKEN=${SERVICE_TOKEN}
    export OS_TENANT_NAME=${OS_TENANT_NAME}
    export OS_USERNAME=${OS_USERNAME}
    export OS_PASSWORD=${OS_PASSWORD}
    export OS_AUTH_URL="http://${KEYSTONE_IP}:5000/v2.0/"
    export SERVICE_ENDPOINT="http://${KEYSTONE_IP}:35357/v2.0"
}

