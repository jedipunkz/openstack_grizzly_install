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
# include functions
# --------------------------------------------------------------------------------------
source ./functions.sh

# --------------------------------------------------------------------------------------
# include each paramters of conf file.
# --------------------------------------------------------------------------------------
if [[ "$2" = "quantum" ]]; then
    source ./deploy_with_quantum.conf
elif [[ "$2" = "nova-network" ]]; then
    source ./deploy_with_nova-network.conf
else
    echo "network type must be : quantum or nova-network."
    exit 1
fi

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
    
    # Adding Roles to Users in Tenants
#    USER_LIST_ID_ADMIN=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from user where name = 'admin'" --skip-column-name --silent`
#    ROLE_LIST_ID_ADMIN=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from role where name = 'admin'" --skip-column-name --silent`
#    TENANT_LIST_ID_ADMIN=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from tenant where name = 'admin'" --skip-column-name --silent`
#    
#    USER_LIST_ID_NOVA=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from user where name = 'nova'" --skip-column-name --silent`
#    TENANT_LIST_ID_SERVICE=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from tenant where name = 'service'" --skip-column-name --silent`
#    
#    USER_LIST_ID_GLANCE=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from user where name = 'glance'" --skip-column-name --silent`
#    USER_LIST_ID_CINDER=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from user where name = 'cinder'" --skip-column-name --silent`
#    USER_LIST_ID_DEMO=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from user where name = 'demo'" --skip-column-name --silent`
#    
#    ROLE_LIST_ID_MEMBER=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from role where name = 'Member'" --skip-column-name --silent`
#    if [[ "$1" = "quantum" ]]; then
#        USER_LIST_ID_QUANTUM=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from user where name = 'quantum'" --skip-column-name --silent`
#    fi
    
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
    
    # get service id for each service
#    SERVICE_LIST_ID_EC2=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from service where type='ec2'" --skip-column-name --silent`
#    SERVICE_LIST_ID_IMAGE=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from service where type='image'" --skip-column-name --silent`
#    SERVICE_LIST_ID_VOLUME=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from service where type='volume'" --skip-column-name --silent`
#    SERVICE_LIST_ID_IDENTITY=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from service where type='identity'" --skip-column-name --silent`
#    SERVICE_LIST_ID_COMPUTE=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from service where type='compute'" --skip-column-name --silent`
#    if [[ "$1" = "quantum" ]]; then
#        SERVICE_LIST_ID_NETWORK=`mysql -u root -p${MYSQL_PASS} keystone -e "select id from service where type='network'" --skip-column-name --silent`
#    fi
    
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
# install openvswitch
# --------------------------------------------------------------------------------------
function openvswitch_setup() {
    install_package openvswitch-switch openvswitch-datapath-dkms
    # create bridge interfaces
    ovs-vsctl add-br br-int
    ovs-vsctl add-br br-eth1
    ovs-vsctl add-port br-eth1 ${DATA_NIC}
    ovs-vsctl add-br br-ex
    ovs-vsctl add-port br-ex ${PUBLIC_NIC}
}

# --------------------------------------------------------------------------------------
# install quantum
# --------------------------------------------------------------------------------------
function allinone_quantum_setup() {
    # install packages
    install_package quantum-server quantum-plugin-openvswitch quantum-plugin-openvswitch-agent dnsmasq quantum-dhcp-agent quantum-l3-agent

    # create database for quantum
    mysql -u root -p${MYSQL_PASS} -e "CREATE DATABASE quantum;"
    mysql -u root -p${MYSQL_PASS} -e "GRANT ALL ON quantum.* TO '${DB_QUANTUM_USER}'@'%' IDENTIFIED BY '${DB_QUANTUM_PASS}';"
    
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/metadata_agent.ini > /etc/quantum/metadata_agent.ini
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/api-paste.ini > /etc/quantum/api-paste.ini
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<CONTROLLER_NODE_PUB_IP>#${CONTROLLER_NODE_PUB_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/l3_agent.ini > /etc/quantum/l3_agent.ini

    sed -e "s#<DB_IP>#${DB_IP}#" -e "s#<QUANTUM_IP>#${QUANUTM_IP}#" $BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini > /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini

    # restart processes
    restart_service quantum-server
    restart_service quantum-plugin-openvswitch-agent
    restart_service quantum-dhcp-agent
    restart_service quantum-l3-agent
}

# --------------------------------------------------------------------------------------
# install quantum for controller node
# --------------------------------------------------------------------------------------
function controller_quantum_setup() {
    # install packages
    install_package quantum-server quantum-plugin-openvswitch
    # create database for quantum
    mysql -u root -p${MYSQL_PASS} -e "CREATE DATABASE quantum;"
    mysql -u root -p${MYSQL_PASS} -e "GRANT ALL ON quantum.* TO 'quantumUser'@'%' IDENTIFIED BY 'quantumPass';"

    sed -e "s#<DB_IP>#${DB_IP}#" -e "s#<QUANTUM_IP>#${QUANUTM_IP}#" $BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini.controller > /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/api-paste.ini > /etc/quantum/api-paste.ini
    
    # restart process
    restart_service quantum-server
}

# --------------------------------------------------------------------------------------
# install quantum for network node
# --------------------------------------------------------------------------------------
function network_quantum_setup() {
    # install packages
    install_package mysql-client
    install_package quantum-plugin-openvswitch-agent quantum-dhcp-agent quantum-l3-agent quantum-metadata-agent
    
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/metadata_agent.ini > /etc/quantum/metadata_agent.ini
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/api-paste.ini > /etc/quantum/api-paste.ini
    sed -e "s#<KEYSTONE_IP>#${KEYSTONE_IP}#" -e "s#<CONTROLLER_NODE_PUB_IP>#${CONTROLLER_NODE_PUB_IP}#" -e "s#<SERVICE_TENANT_NAME>#${SERVICE_TENANT_NAME}#" -e "s#<SERVICE_PASSWORD>#${SERVICE_PASSWORD}#" $BASE_DIR/conf/etc.quantum/l3_agent.ini > /etc/quantum/l3_agent.ini
    sed -e "s#<DB_IP>#${DB_IP}#" -e "s#<QUANTUM_IP>#${NETWORK_NODE_IP}#" $BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini > /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini
    sed -e "s#<CONTROLLER_IP>#${CONTROLLER_NODE_IP}#" $BASE_DIR/conf/etc.quantum/quantum.conf > /etc/quantum/quantum.conf

    # restart processes
    cd /etc/init.d/; for i in $( ls quantum-* ); do sudo service $i restart; done
}

# --------------------------------------------------------------------------------------
# create network via quantum
# --------------------------------------------------------------------------------------
function create_network() {
    # create internal network
    TENANT_ID=$(keystone tenant-list | grep " service " | get_field 1)
    INT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} int_net | grep ' id ' | get_field 2)
    INT_SUBNET_ID=$(quantum subnet-create --tenant-id ${TENANT_ID} --ip_version 4 --gateway ${INT_NET_GATEWAY} ${INT_NET_ID} ${INT_NET_RANGE} | grep ' id ' | get_field 2)
    quantum subnet-update ${INT_SUBNET_ID} list=true --dns_nameservers 8.8.8.8 8.8.4.4
    INT_ROUTER_ID=$(quantum router-create --tenant-id ${TENANT_ID} router-demo | grep ' id ' | get_field 2)
    INT_L3_AGENT_ID=$(quantum agent-list | grep ' L3 agent ' | get_field 1)
    quantum l3-agent-router-add ${INT_L3_AGENT_ID} router-demo
    quantum router-interface-add ${INT_ROUTER_ID} ${INT_SUBNET_ID}
    # create external network
    EXT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} ext_net -- --router:external=True | grep ' id ' | get_field 2)
    quantum subnet-create --tenant-id ${TENANT_ID} --gateway=${EXT_NET_GATEWAY} --allocation-pool start=${EXT_NET_START},end=${EXT_NET_END} ${EXT_NET_ID} ${EXT_NET_RANGE} -- --enable_dhcp=False
    quantum router-gateway-set ${INT_ROUTER_ID} ${EXT_NET_ID}
}

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

# --------------------------------------------------------------------------------------
# Main Function
# --------------------------------------------------------------------------------------
if [[ "$2" = "nova-network" ]]; then
    case "$1" in
        allinone)
            NOVA_IP=${HOST_IP};     check_para ${NOVA_IP}
            CINDER_IP=${HOST_IP};   check_para ${CINDER_IP}
            DB_IP=${HOST_IP};       check_para ${DB_IP}
            KEYSTONE_IP=${HOST_IP}; check_para ${KEYSTONE_IP}
            GLANCE_IP=${HOST_IP};   check_para ${GLANCE_IP}
            QUANTUM_IP=${HOST_IP};  check_para ${QUANTUM_IP}
            RABBIT_IP=${HOST_IP};   check_para ${RABBIT_IP}
            check_env 
            shell_env allinone
            init
            mysql_setup
            keystone_setup nova-network
            glance_setup
            os_add
            controller_nova_setup_nova-network
            cinder_setup
            horizon_setup
            create_network_nova-network
            scgroup_allow allinone
            echo "Setup for all in one node has done.:D"
            ;;
        controller)
            NOVA_IP=${CONTROLLER_NODE_IP};     check_para ${NOVA_IP}
            CINDER_IP=${CONTROLLER_NODE_IP};   check_para ${CINDER_IP}
            DB_IP=${CONTROLLER_NODE_IP};       check_para ${DB_IP}
            KEYSTONE_IP=${CONTROLLER_NODE_IP}; check_para ${KEYSTONE_IP}
            GLANCE_IP=${CONTROLLER_NODE_IP};   check_para ${GLANCE_IP}
            QUANTUM_IP=${CONTROLLER_NODE_IP};  check_para ${QUANTUM_IP}
            RABBIT_IP=${CONTROLLER_NODE_IP};   check_para ${RABBIT_IP}
            check_env 
            shell_env separate
            init
            mysql_setup
            keystone_setup nova-network
            glance_setup
            os_add
            controller_nova_setup_nova-network
            cinder_setup
            horizon_setup
            scgroup_allow controller
            echo "Setup for controller node has done.:D"
            ;;
        compute)
            NOVA_IP=${CONTROLLER_NODE_IP};     check_para ${NOVA_IP}
            CINDER_IP=${CONTROLLER_NODE_IP};   check_para ${CINDER_IP}
            DB_IP=${CONTROLLER_NODE_IP};       check_para ${DB_IP}
            KEYSTONE_IP=${CONTROLLER_NODE_IP}; check_para ${KEYSTONE_IP}
            GLANCE_IP=${CONTROLLER_NODE_IP};   check_para ${GLANCE_IP}
            QUANTUM_IP=${CONTROLLER_NODE_IP};  check_para ${QUANTUM_IP}
            RABBIT_IP=${CONTROLLER_NODE_IP};   check_para ${RABBIT_IP}
            check_env 
            shell_env separate
            init
            compute_nova_setup_nova-network
            create_network_nova-network
            echo "Setup for compute node has done.:D"
            ;;
        create_network)
            if [[ "${HOST_IP}" ]]; then
                NOVA_IP=${HOST_IP};            check_para ${NOVA_IP}
                CINDER_IP=${HOST_IP};          check_para ${CINDER_IP}
                DB_IP=${HOST_IP};              check_para ${DB_IP}
                KEYSTONE_IP=${HOST_IP};        check_para ${KEYSTONE_IP}
                GLANCE_IP=${HOST_IP};          check_para ${GLANCE_IP}
                QUANTUM_IP=${HOST_IP};         check_para ${QUANTUM_IP}
            elif [[ "${CONTROLLER_NODE_IP}" ]]; then
                NOVA_IP=${CONTROLLER_NODE_IP};            check_para ${NOVA_IP}
                CINDER_IP=${CONTROLLER_NODE_IP};          check_para ${CINDER_IP}
                DB_IP=${CONTROLLER_NODE_IP};              check_para ${DB_IP}
                KEYSTONE_IP=${CONTROLLER_NODE_IP};        check_para ${KEYSTONE_IP}
                GLANCE_IP=${CONTROLLER_NODE_IP};          check_para ${GLANCE_IP}
                QUANTUM_IP=${CONTROLLER_NODE_IP};         check_para ${QUANTUM_IP}
            else
                print_syntax
            fi
 
            check_env
            shell_env
            create_network_nova-network
            ;;
        *)
            print_syntax
            ;;
    esac
elif [[ "$2" = "quantum" ]]; then
    case "$1" in
        allinone)
            NOVA_IP=${HOST_IP};                     check_para ${NOVA_IP}
            CINDER_IP=${HOST_IP};                   check_para ${CINDER_IP}
            DB_IP=${HOST_IP};                       check_para ${DB_IP}
            KEYSTONE_IP=${HOST_IP};                 check_para ${KEYSTONE_IP}
            GLANCE_IP=${HOST_IP};                   check_para ${GLANCE_IP}
            QUANTUM_IP=${HOST_IP};                  check_para ${QUANTUM_IP}
            RABBIT_IP=${HOST_IP};                   check_para ${RABBIT_IP}
            CONTROLLER_NODE_PUB_IP=${HOST_PUB_IP};  check_para ${CONTROLLER_NODE_PUB_IP}
            KEYSTONE_PUB_IP=${HOST_PUB_IP};         check_para ${KEYSTONE_PUB_IP}
            check_env 
            shell_env allinone
            init
            mysql_setup
            keystone_setup quantum
            glance_setup
            os_add
            openvswitch_setup
            allinone_quantum_setup
            allinone_nova_setup
            cinder_setup
            horizon_setup
            create_network
            scgroup_allow allinone
            echo "Setup for all in one node has done.:D"
            ;;
        controller)
            NOVA_IP=${CONTROLLER_NODE_IP};              check_para ${NOVA_IP}
            CINDER_IP=${CONTROLLER_NODE_IP};            check_para ${CINDER_IP}
            DB_IP=${CONTROLLER_NODE_IP};                check_para ${DB_IP}
            KEYSTONE_IP=${CONTROLLER_NODE_IP};          check_para ${KEYSTONE_IP}
            GLANCE_IP=${CONTROLLER_NODE_IP};            check_para ${GLANCE_IP}
            QUANTUM_IP=${CONTROLLER_NODE_IP};           check_para ${QUANTUM_IP}
            RABBIT_IP=${CONTROLLER_NODE_IP};            check_para ${RABBIT_IP}
            KEYSTONE_PUB_IP=${CONTROLLER_NODE_PUB_IP};  check_para ${KEYSTONE_PUB_IP}
            check_env 
            shell_env separate
            init
            mysql_setup
            keystone_setup quantum controller
            glance_setup
            os_add
            controller_quantum_setup
            controller_nova_setup
            cinder_setup
            horizon_setup
            scgroup_allow controller
            echo "Setup for controller node has done.:D"
            ;;
        network)
            NOVA_IP=${CONTROLLER_NODE_IP};     check_para ${NOVA_IP}
            CINDER_IP=${CONTROLLER_NODE_IP};   check_para ${CINDER_IP}
            DB_IP=${CONTROLLER_NODE_IP};       check_para ${DB_IP}
            KEYSTONE_IP=${CONTROLLER_NODE_IP}; check_para ${KEYSTONE_IP}
            GLANCE_IP=${CONTROLLER_NODE_IP};   check_para ${GLANCE_IP}
            QUANTUM_IP=${CONTROLLER_NODE_IP};  check_para ${QUANTUM_IP}
            RABBIT_IP=${CONTROLLER_NODE_IP};   check_para ${RABBIT_IP}
            check_env 
            shell_env separate
            init
            openvswitch_setup
            network_quantum_setup
            create_network
            echo "Setup for network node has done.:D"
            ;;
        compute)
            NOVA_IP=${CONTROLLER_NODE_IP};     check_para ${NOVA_IP}
            CINDER_IP=${CONTROLLER_NODE_IP};   check_para ${CINDER_IP}
            DB_IP=${CONTROLLER_NODE_IP};       check_para ${DB_IP}
            KEYSTONE_IP=${CONTROLLER_NODE_IP}; check_para ${KEYSTONE_IP}
            GLANCE_IP=${CONTROLLER_NODE_IP};   check_para ${GLANCE_IP}
            QUANTUM_IP=${CONTROLLER_NODE_IP};  check_para ${QUANTUM_IP}
            RABBIT_IP=${CONTROLLER_NODE_IP};   check_para ${RABBIT_IP}
            check_env
            shell_env separate
            init
            compute_nova_setup
            echo "Setup for compute node has done.:D"
            ;;
        create_network)
            if [[ "${HOST_IP}" ]]; then
                NOVA_IP=${HOST_IP};                check_para ${NOVA_IP}
                CINDER_IP=${HOST_IP};              check_para ${CINDER_IP}
                DB_IP=${HOST_IP};                  check_para ${DB_IP}
                KEYSTONE_IP=${HOST_IP};            check_para ${KEYSTONE_IP}
                GLANCE_IP=${HOST_IP};              check_para ${GLANCE_IP}
                QUANTUM_IP=${HOST_IP};             check_para ${QUANTUM_IP}
            elif [[ "${CONTROLLER_NODE_IP}" ]]; then
                NOVA_IP=${CONTROLLER_NODE_IP};     check_para ${NOVA_IP}
                CINDER_IP=${CONTROLLER_NODE_IP};   check_para ${CINDER_IP}
                DB_IP=${CONTROLLER_NODE_IP};       check_para ${DB_IP}
                KEYSTONE_IP=${CONTROLLER_NODE_IP}; check_para ${KEYSTONE_IP}
                GLANCE_IP=${CONTROLLER_NODE_IP};   check_para ${GLANCE_IP}
                QUANTUM_IP=${CONTROLLER_NODE_IP};  check_para ${QUANTUM_IP}
            else
                print_syntax
            fi

            check_env
            shell_env allinone
            create_network
            ;;
        *)
            print_syntax
            ;;
    esac
else
    print_syntax
fi

exit 0
