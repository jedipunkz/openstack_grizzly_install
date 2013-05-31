#!/usr/bin/env bash

# --------------------------------------------------------------------------------------
# initialization function
# --------------------------------------------------------------------------------------
function init() {
    # at first, update package repository cache
    apt-get update

    # install ntp
    install_package ntp
    cp $BASE_DIR/conf/etc.ntp.conf /etc/ntp.conf

    # install misc software
    apt-get install -y vlan bridge-utils

    # use Ubuntu Cloud Archive repository
    # this script needs Ubuntu Cloud Archive for Grizzly, so we are using 12.04 LTS.
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

    # create openstackrc for 'demo' user. this user is useful for horizon or to access each APIs by demo.
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
    # install mysql and rabbitmq
    install_package mysql-server python-mysqldb

    # enable to access from the other nodes to local mysqld via network
    sed -i -e  "s/^\(bind-address\s*=\).*/\1 0.0.0.0/" /etc/mysql/my.cnf
    restart_service mysql

    # misc software
    install_package rabbitmq-server
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

    # set configuration file
    setconf infile:$BASE_DIR/conf/etc.keystone/keystone.conf \
        outfile:/etc/keystone/keystone.conf \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<DB_KEYSTONE_USER>:${DB_KEYSTONE_USER}" \
        "<DB_KEYSTONE_PASS>:${DB_KEYSTONE_PASS}"

    # restart keystone
    restart_service keystone
    # input keystone database to mysqld
    keystone-manage db_sync
    
    # create tenants
    TENANT_ID_ADMIN=$(keystone tenant-create --name admin | grep ' id ' | get_field 2)
    TENANT_ID_SERVICE=$(keystone tenant-create --name service | grep ' id ' | get_field 2)
    
    # create users
    USER_ID_ADMIN=$(keystone user-create --name admin --pass ${ADMIN_PASSWORD} --tenant-id ${TENANT_ID_SERVICE} --email admin@example.com | grep ' id ' | get_field 2)
    USER_ID_NOVA=$(keystone user-create --name nova --pass ${SERVICE_PASSWORD} --tenant-id ${TENANT_ID_SERVICE} --email admin@example.com | grep ' id ' | get_field 2)
    USER_ID_GLANCE=$(keystone user-create --name glance --pass ${SERVICE_PASSWORD} --tenant-id ${TENANT_ID_SERVICE} --email admin@example.com | grep ' id ' | get_field 2)
    USER_ID_CINDER=$(keystone user-create --name cinder --pass ${SERVICE_PASSWORD} --tenant-id ${TENANT_ID_SERVICE} --email admin@example.com | grep ' id ' | get_field 2)
    USER_ID_DEMO=$(keystone user-create --name ${DEMO_USER} --pass ${DEMO_PASSWORD} --tenant-id ${TENANT_ID_SERVICE} --email demo@example.com | grep ' id ' | get_field 2)
    if [[ "$1" = "quantum" ]]; then
        USER_ID_QUANTUM=$(keystone user-create --name quantum --pass ${SERVICE_PASSWORD} --tenant-id ${TENANT_ID_SERVICE} --email admin@example.com | grep ' id ' | get_field 2)
    fi
    
    # create roles
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

    # check service list that we just made
    keystone service-list
    
    # create endpoints
    if [[ "$2" = "controller" ]]; then
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_EC2 --publicurl "http://${CONTROLLER_NODE_PUB_IP}:8773/services/Cloud" --adminurl "http://${CONTROLLER_NODE_IP}:8773/services/Admin" --internalurl "http://${CONTROLLER_NODE_IP}:8773/services/Cloud"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_IDENTITY --publicurl "http://${CONTROLLER_NODE_PUB_IP}:5000/v2.0" --adminurl "http://${CONTROLLER_NODE_IP}:35357/v2.0" --internalurl "http://${CONTROLLER_NODE_IP}:5000/v2.0"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_VOLUME --publicurl "http://${CONTROLLER_NODE_PUB_IP}:8776/v1/\$(tenant_id)s" --adminurl "http://${CONTROLLER_NODE_IP}:8776/v1/\$(tenant_id)s" --internalurl "http://${CONTROLLER_NODE_IP}:8776/v1/\$(tenant_id)s"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_IMAGE --publicurl "http://${CONTROLLER_NODE_PUB_IP}:9292/v2" --adminurl "http://${CONTROLLER_NODE_IP}:9292/v2" --internalurl "http://${CONTROLLER_NODE_IP}:9292/v2"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_COMPUTE --publicurl "http://${CONTROLLER_NODE_PUB_IP}:8774/v2/\$(tenant_id)s" --adminurl "http://${CONTROLLER_NODE_IP}:8774/v2/\$(tenant_id)s" --internalurl "http://${CONTROLLER_NODE_IP}:8774/v2/\$(tenant_id)s"
        if [[ "$1" = "quantum" ]]; then
            keystone endpoint-create --region myregion --service-id $SERVICE_ID_QUANTUM --publicurl "http://${CONTROLLER_NODE_PUB_IP}:9696/" --adminurl "http://${CONTROLLER_NODE_IP}:9696/" --internalurl "http://${CONTROLLER_NODE_IP}:9696/"
        fi
    else
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_EC2 --publicurl "http://${CONTROLLER_NODE_IP}:8773/services/Cloud" --adminurl "http://${CONTROLLER_NODE_IP}:8773/services/Admin" --internalurl "http://${CONTROLLER_NODE_IP}:8773/services/Cloud"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_IDENTITY --publicurl "http://${CONTROLLER_NODE_IP}:5000/v2.0" --adminurl "http://${CONTROLLER_NODE_IP}:35357/v2.0" --internalurl "http://${CONTROLLER_NODE_IP}:5000/v2.0"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_VOLUME --publicurl "http://${CONTROLLER_NODE_IP}:8776/v1/\$(tenant_id)s" --adminurl "http://${CONTROLLER_NODE_IP}:8776/v1/\$(tenant_id)s" --internalurl "http://${CONTROLLER_NODE_IP}:8776/v1/\$(tenant_id)s"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_IMAGE --publicurl "http://${CONTROLLER_NODE_IP}:9292/v2" --adminurl "http://${CONTROLLER_NODE_IP}:9292/v2" --internalurl "http://${CONTROLLER_NODE_IP}:9292/v2"
        keystone endpoint-create --region myregion --service_id $SERVICE_ID_COMPUTE --publicurl "http://${CONTROLLER_NODE_IP}:8774/v2/\$(tenant_id)s" --adminurl "http://${CONTROLLER_NODE_IP}:8774/v2/\$(tenant_id)s" --internalurl "http://${CONTROLLER_NODE_IP}:8774/v2/\$(tenant_id)s"
        if [[ "$1" = "quantum" ]]; then
            keystone endpoint-create --region myregion --service-id $SERVICE_ID_QUANTUM --publicurl "http://${CONTROLLER_NODE_IP}:9696/" --adminurl "http://${CONTROLLER_NODE_IP}:9696/" --internalurl "http://${CONTROLLER_NODE_IP}:9696/"
        fi
    fi

    # check endpoint list that we just made
    keystone endpoint-list
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

    # set configuration files
    setconf infile:$BASE_DIR/conf/etc.glance/glance-api.conf \
        outfile:/etc/glance/glance-api.conf \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" "<DB_IP>:${DB_IP}" \
        "<DB_GLANCE_USER>:${DB_GLANCE_USER}" \
        "<DB_GLANCE_PASS>:${DB_GLANCE_PASS}"
    setconf infile:$BASE_DIR/conf/etc.glance/glance-registry.conf \
        outfile:/etc/glance/glance-registry.conf \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" "<DB_IP>:${DB_IP}" \
        "<DB_GLANCE_USER>:${DB_GLANCE_USER}" \
        "<DB_GLANCE_PASS>:${DB_GLANCE_PASS}"
    setconf infile:$BASE_DIR/conf/etc.glance/glance-registry-paste.ini \
        outfile:/etc/glance/glance-registry-paste.ini \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"
    setconf infile:$BASE_DIR/conf/etc.glance/glance-api-paste.ini \
        outfile:/etc/glance/glance-api-paste.ini \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"

    
    # restart process and syncing database
    restart_service glance-registry
    restart_service glance-api
    
    # input glance database to mysqld
    glance-manage db_sync
}

# --------------------------------------------------------------------------------------
# add os image
# --------------------------------------------------------------------------------------
function os_add () {
    # backup exist os image
    if [[ -f ./os.img ]]; then
        mv ./os.img ./os.img.bk
    fi
    
    # download cirros os image
    wget --no-check-certificate ${OS_IMAGE_URL} -O ./os.img
    
    # add os image to glance
    glance image-create --name="${OS_IMAGE_NAME}" --is-public true --container-format bare --disk-format qcow2 < ./os.img
}

# --------------------------------------------------------------------------------------
# install nova for all in one with quantum
# --------------------------------------------------------------------------------------
function allinone_nova_setup() {
    # install kvm and the others packages
    install_package kvm libvirt-bin pm-utils
    restart_service dbus
    sleep 3
    #virsh net-destroy default
    virsh net-undefine default
    restart_service libvirt-bin

    # install nova packages
    install_package nova-api nova-cert novnc nova-consoleauth nova-scheduler nova-novncproxy nova-doc nova-conductor nova-compute-kvm
    # create database for nova
    mysql -u root -p${MYSQL_PASS} -e "CREATE DATABASE nova;"
    mysql -u root -p${MYSQL_PASS} -e "GRANT ALL ON nova.* TO '${DB_NOVA_USER}'@'%' IDENTIFIED BY '${DB_NOVA_PASS}';"

    # set configuration files
    setconf infile:$BASE_DIR/conf/etc.nova/api-paste.ini outfile:/etc/nova/api-paste.ini \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"
    setconf infile:$BASE_DIR/conf/etc.nova/nova.conf outfile:/etc/nova/nova.conf \
        "<METADATA_LISTEN>:${CONTROLLER_NODE_IP}" "<CONTROLLER_IP>:${CONTROLLER_NODE_IP}" \
        "<VNC_IP>:${CONTROLLER_NODE_IP}" "<DB_IP>:${DB_IP}" "<DB_NOVA_USER>:${DB_NOVA_USER}" \
        "<DB_NOVA_PASS>:${DB_NOVA_PASS}" "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}" "<LOCAL_IP>:${CONTROLLER_NODE_IP}" \
        "<CINDER_IP>:${CONTROLLER_NODE_IP}"

    cp $BASE_DIR/conf/etc.nova/nova-compute.conf /etc/nova/nova-compute.conf

    # input nova database to mysqld
    nova-manage db sync
    
    # restart all of nova services
    cd /etc/init.d/; for i in $( ls nova-* ); do sudo service $i restart; done
    
    # check nova service list
    nova-manage service list
}

# --------------------------------------------------------------------------------------
# install nova for controller node with quantum
# --------------------------------------------------------------------------------------
function controller_nova_setup() {
    # install packages
    install_package nova-api nova-cert novnc nova-consoleauth nova-scheduler nova-novncproxy nova-doc nova-conductor

    # create database for nova
    mysql -u root -p${MYSQL_PASS} -e "CREATE DATABASE nova;"
    mysql -u root -p${MYSQL_PASS} -e "GRANT ALL ON nova.* TO '${DB_NOVA_USER}'@'%' IDENTIFIED BY '${DB_NOVA_PASS}';"
    
    # set configuration files for nova
    setconf infile:$BASE_DIR/conf/etc.nova/api-paste.ini outfile:/etc/nova/api-paste.ini \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"
    setconf infile:$BASE_DIR/conf/etc.nova/nova.conf outfile:/etc/nova/nova.conf \
        "<METADATA_LISTEN>:${CONTROLLER_NODE_IP}" "<CONTROLLER_IP>:${CONTROLLER_NODE_IP}" \
        "<VNC_IP>:${CONTROLLER_NODE_PUB_IP}" "<DB_IP>:${DB_IP}" "<DB_NOVA_USER>:${DB_NOVA_USER}" \
        "<DB_NOVA_PASS>:${DB_NOVA_PASS}" "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}" "<LOCAL_IP>:${CONTROLLER_NODE_IP}" \
        "<CINDER_IP>:${CONTROLLER_NODE_IP}"
        

    # input nova database to mysqld
    nova-manage db sync
    
    # restart all of nova services
    cd /etc/init.d/; for i in $( ls nova-* ); do sudo service $i restart; done
    
    # check nova service list
    nova-manage service list
}

# --------------------------------------------------------------------------------------
# install nova for compute node with quantum
# --------------------------------------------------------------------------------------
function compute_nova_setup() {
    # install dependency packages
    install_package vlan bridge-utils kvm libvirt-bin pm-utils sysfsutils
    restart_service dbus
    sleep 3
    #virsh net-destroy default
    virsh net-undefine default

    # enable live migration
    cp $BASE_DIR/conf/etc.libvirt/libvirtd.conf /etc/libvirt/libvirtd.conf
    sed -i 's/^env\ libvirtd_opts=\"-d\"/env\ libvirtd_opts=\"-d\ -l\"/g' /etc/init/libvirt-bin.conf
    sed -i 's/libvirtd_opts=\"-d\"/libvirtd_opts=\"-d\ -l\"/g' /etc/default/libvirt-bin
    restart_service libvirt-bin

    #
    # OpenvSwitch
    #
    # install openvswitch and add bridge interfaces
    install_package openvswitch-switch

    # adding bridge and port
    ovs-vsctl add-br br-int
    ovs-vsctl add-br br-eth1
    ovs-vsctl add-port br-eth1 ${DATANETWORK_NIC_COMPUTE_NODE}

    #
    # Quantum
    #
    # install openvswitch quantum plugin
    install_package quantum-plugin-openvswitch-agent quantum-lbaas-agent

    # set configuration files
    if [[ "${NETWORK_TYPE}" = 'gre' ]]; then
        setconf infile:$BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini.gre \
            outfile:/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini \
            "<DB_IP>:${DB_IP}" "<QUANTUM_IP>:${COMPUTE_NODE_IP}"
    elif [[ "${NETWORK_TYPE}" = 'vlan' ]]; then
        setconf infile:$BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini.vlan \
            outfile:/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini \
            "<DB_IP>:${DB_IP}"
    else
        echo "NETWORK_TYPE must be 'vlan' or 'gre'."
        exit 1
    fi
        
    setconf infile:$BASE_DIR/conf/etc.quantum/quantum.conf \
        outfile:/etc/quantum/quantum.conf \
        "<CONTROLLER_IP>:${CONTROLLER_NODE_IP}"

    # restart ovs agent
    service quantum-plugin-openvswitch-agent restart

    #
    # Nova
    #
    # instll nova package
    install_package nova-compute-kvm

    # set configuration files
    setconf infile:$BASE_DIR/conf/etc.nova/api-paste.ini \
        outfile:/etc/nova/api-paste.ini \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"
    setconf infile:$BASE_DIR/conf/etc.nova/nova.conf \
        outfile:/etc/nova/nova.conf \
        "<METADATA_LISTEN>:127.0.0.1" "<CONTROLLER_IP>:${CONTROLLER_NODE_IP}" \
        "<VNC_IP>:${CONTROLLER_NODE_PUB_IP}" "<DB_IP>:${DB_IP}" \
        "<DB_NOVA_USER>:${DB_NOVA_USER}" "<DB_NOVA_PASS>:${DB_NOVA_PASS}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}" \
        "<LOCAL_IP>:${COMPUTE_NODE_IP}" "<CINDER_IP>:${CONTROLLER_NODE_IP}"
    cp $BASE_DIR/conf/etc.nova/nova-compute.conf /etc/nova/nova-compute.conf

    # restart all of nova services
    cd /etc/init.d/; for i in $( ls nova-* ); do sudo service $i restart; done

    # check nova services
    nova-manage service list
}

# --------------------------------------------------------------------------------------
# install cinder
# --------------------------------------------------------------------------------------
function cinder_setup() {
    # install packages
    install_package cinder-api cinder-scheduler cinder-volume iscsitarget open-iscsi iscsitarget-dkms

    # setup iscsi
    setconf infile:/etc/default/iscsitarget "false:true"
    service iscsitarget start
    service open-iscsi start
    
    # create database for cinder
    mysql -uroot -p${MYSQL_PASS} -e "CREATE DATABASE cinder;"
    mysql -uroot -p${MYSQL_PASS} -e "GRANT ALL ON cinder.* TO '${DB_CINDER_USER}'@'%' IDENTIFIED BY '${DB_CINDER_PASS}';"
    
    # set configuration files
    if [[ "$1" = "controller" ]]; then
        setconf infile:$BASE_DIR/conf/etc.cinder/api-paste.ini \
            outfile:/etc/cinder/api-paste.ini \
            "<KEYSTONE_IP>:${KEYSTONE_IP}" \
            "<CONTROLLER_PUB_IP>:${CONTROLLER_NODE_PUB_IP}" \
            "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
            "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"
    elif [[ "$1" = "allinone" ]]; then
        setconf infile:$BASE_DIR/conf/etc.cinder/api-paste.ini \
            outfile:/etc/cinder/api-paste.ini \
            "<KEYSTONE_IP>:${KEYSTONE_IP}" \
            "<CONTROLLER_PUB_IP>:${CONTROLLER_NODE_IP}" \
            "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
            "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"
    else
        echo "Warning: Mode must be 'allinone' or 'controller'."
        exit 1
    fi
    setconf infile:$BASE_DIR/conf/etc.cinder/cinder.conf \
        outfile:/etc/cinder/cinder.conf \
        "<DB_IP>:${DB_IP}" "<DB_CINDER_USER>:${DB_CINDER_USER}" \
        "<DB_CINDER_PASS>:${DB_CINDER_PASS}" \
        "<CINDER_IP>:${CONTROLLER_NODE_IP}"

    # input database for cinder
    cinder-manage db sync

    if echo "$CINDER_VOLUME" | grep "loop" ; then
        dd if=/dev/zero of=/var/lib/cinder/volumes-disk bs=2 count=0 seek=7G
        FILE=/var/lib/cinder/volumes-disk
        modprobe loop
        losetup $CINDER_VOLUME $FILE
        pvcreate $CINDER_VOLUME
        vgcreate cinder-volumes $CINDER_VOLUME
    else
        # create pyshical volume and volume group
        pvcreate ${CINDER_VOLUME}
        vgcreate cinder-volumes ${CINDER_VOLUME}
    fi

    # disable tgt daemon
    stop_service tgt
    mv /etc/init/tgt.conf /etc/init/tgt.conf.disabled
    restart_service iscsitarget

    # restart all of cinder services
    restart_service cinder-volume
    restart_service cinder-api
    restart_service cinder-scheduler
}

# --------------------------------------------------------------------------------------
# install horizon
# --------------------------------------------------------------------------------------
function horizon_setup() {
    # install horizon packages
    install_package openstack-dashboard memcached

    # set configuration file
    cp $BASE_DIR/conf/etc.openstack-dashboard/local_settings.py /etc/openstack-dashboard/local_settings.py
    
    # restart horizon services
    restart_service apache2
    restart_service memcached
}

# --------------------------------------------------------------------------------------
#  make seciruty group rule named 'default' to allow SSH and ICMP traffic
# --------------------------------------------------------------------------------------
# this function enable to access to the instances via SSH and ICMP.
# if you want to add more rules named default, you can add it.
function scgroup_allow() {
    # switch to 'demo' user
    # We will use 'demo' user to access each API and instances, so it switch to 'demo'
    # user for security group setup.
    export SERVICE_TOKEN=${SERVICE_TOKEN}
    export OS_TENANT_NAME=service
    export OS_USERNAME=${DEMO_USER}
    export OS_PASSWORD=${DEMO_PASSWORD}
    export OS_AUTH_URL="http://${KEYSTONE_IP}:5000/v2.0/"
    export SERVICE_ENDPOINT="http://${KEYSTONE_IP}:35357/v2.0"

    # add SSH, ICMP allow rules which named 'default'
    nova --no-cache secgroup-add-rule default tcp 22 22 0.0.0.0/0
    nova --no-cache secgroup-add-rule default icmp -1 -1 0.0.0.0/0

    # switch to 'admin' user
    # this script need 'admin' user, so turn back to admin.
    export SERVICE_TOKEN=${SERVICE_TOKEN}
    export OS_TENANT_NAME=${OS_TENANT_NAME}
    export OS_USERNAME=${OS_USERNAME}
    export OS_PASSWORD=${OS_PASSWORD}
    export OS_AUTH_URL="http://${KEYSTONE_IP}:5000/v2.0/"
    export SERVICE_ENDPOINT="http://${KEYSTONE_IP}:35357/v2.0"
}

# --------------------------------------------------------------------------------------
# install openvswitch
# --------------------------------------------------------------------------------------
function openvswitch_setup() {
    install_package openvswitch-switch openvswitch-datapath-dkms
    # create bridge interfaces
    ovs-vsctl add-br br-int
    ovs-vsctl add-br br-eth1
    if [[ "$1" = "network" ]]; then
        ovs-vsctl add-port br-eth1 ${DATANETWORK_NIC_NETWORK_NODE}
    fi
    ovs-vsctl add-br br-ex
    ovs-vsctl add-port br-ex ${PUBLICNETWORK_NIC}
}
