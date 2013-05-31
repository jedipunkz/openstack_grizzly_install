#!/usr/bin/env bash

# --------------------------------------------------------------------------------------
# install quantum
# --------------------------------------------------------------------------------------
function allinone_quantum_setup() {
    # install packages
    install_package quantum-server quantum-plugin-openvswitch quantum-plugin-openvswitch-agent dnsmasq quantum-dhcp-agent quantum-l3-agent quantum-lbaas-agent

    # create database for quantum
    mysql -u root -p${MYSQL_PASS} -e "CREATE DATABASE quantum;"
    mysql -u root -p${MYSQL_PASS} -e "GRANT ALL ON quantum.* TO '${DB_QUANTUM_USER}'@'%' IDENTIFIED BY '${DB_QUANTUM_PASS}';"

    # set configuration files
    setconf infile:$BASE_DIR/conf/etc.quantum/metadata_agent.ini \
        outfile:/etc/quantum/metadata_agent.ini \
        "<CONTROLLER_IP>:127.0.0.1" "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"
    setconf infile:$BASE_DIR/conf/etc.quantum/api-paste.ini \
        outfile:/etc/quantum/api-paste.ini \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"
    setconf infile:$BASE_DIR/conf/etc.quantum/l3_agent.ini \
        outfile:/etc/quantum/l3_agent.ini \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<CONTROLLER_NODE_PUB_IP>:${CONTROLLER_NODE_PUB_IP}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"

    if [[ "${NETWORK_TYPE}" = 'gre' ]]; then
        setconf infile:$BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini.gre \
            outfile:/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini \
            "<DB_IP>:${DB_IP}" "<QUANTUM_IP>:${QUANUTM_IP}"
    elif [[ "${NETWORK_TYPE}" = 'vlan' ]]; then
        setconf infile:$BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini.vlan \
            outfile:/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini \
            "<DB_IP>:${DB_IP}"
    else
        echo "NETWORK_TYPE must be 'vlan' or 'gre'."
        exit 1
    fi
        
    # see BUG https://lists.launchpad.net/openstack/msg23198.html
    # this treat includes secirity problem, but unfortunatly it is needed for quantum now.
    # when you noticed that it is not needed, please comment out these 2 lines.
    cp $BASE_DIR/conf/etc.sudoers.d/quantum_sudoers /etc/sudoers.d/quantum_sudoers
    chmod 440 /etc/sudoers.d/quantum_sudoers

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
    mysql -u root -p${MYSQL_PASS} -e "GRANT ALL ON quantum.* TO '${DB_QUANTUM_USER}'@'%' IDENTIFIED BY '${DB_QUANTUM_PASS}';"

    # set configuration files
    if [[ "${NETWORK_TYPE}" = 'gre' ]]; then
        setconf infile:$BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini.gre.controller \
            outfile:/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini \
            "<DB_IP>:${DB_IP}"
    elif [[ "${NETWORK_TYPE}" = 'vlan' ]]; then
        setconf infile:$BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini.vlan \
            outfile:/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini \
            "<DB_IP>:${DB_IP}"
    else
        echo "NETWORK_TYPE must be 'vlan' or 'gre'."
        exit 1
    fi
    
    setconf infile:$BASE_DIR/conf/etc.quantum/api-paste.ini \
        outfile:/etc/quantum/api-paste.ini \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"
    setconf infile:$BASE_DIR/conf/etc.quantum/quantum.conf \
        outfile:/etc/quantum/quantum.conf \
        "<CONTROLLER_IP>:localhost"
    
    # restart process
    restart_service quantum-server
}

# --------------------------------------------------------------------------------------
# install quantum for network node
# --------------------------------------------------------------------------------------
function network_quantum_setup() {
    # install packages
    install_package mysql-client
    install_package quantum-plugin-openvswitch-agent quantum-dhcp-agent quantum-l3-agent quantum-metadata-agent quantum-lbaas-agent

    # set configuration files
    setconf infile:$BASE_DIR/conf/etc.quantum/metadata_agent.ini \
        outfile:/etc/quantum/metadata_agent.ini \
        "<CONTROLLER_IP>:${CONTROLLER_NODE_IP}" \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}#"
    setconf infile:$BASE_DIR/conf/etc.quantum/api-paste.ini \
        outfile:/etc/quantum/api-paste.ini \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"
    setconf infile:$BASE_DIR/conf/etc.quantum/l3_agent.ini \
        outfile:/etc/quantum/l3_agent.ini \
        "<KEYSTONE_IP>:${KEYSTONE_IP}" \
        "<CONTROLLER_NODE_PUB_IP>:${CONTROLLER_NODE_PUB_IP}" \
        "<SERVICE_TENANT_NAME>:${SERVICE_TENANT_NAME}" \
        "<SERVICE_PASSWORD>:${SERVICE_PASSWORD}"
    setconf infile:$BASE_DIR/conf/etc.quantum/quantum.conf \
        outfile:/etc/quantum/quantum.conf \
        "<CONTROLLER_IP>:${CONTROLLER_NODE_IP}"
    
    if [[ "${NETWORK_TYPE}" = 'gre' ]]; then
        setconf infile:$BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini.gre \
            outfile:/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini \
            "<DB_IP>:${DB_IP}" "<QUANTUM_IP>:${NETWORK_NODE_IP}"
    elif [[ "${NETWORK_TYPE}" = 'vlan' ]]; then
        setconf infile:$BASE_DIR/conf/etc.quantum.plugins.openvswitch/ovs_quantum_plugin.ini.vlan \
            outfile:/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini \
            "<DB_IP>:${DB_IP}"
    else
        echo "NETWORK_TYPE must be 'vlan' or 'gre'."
        exit 1
    fi

    # see BUG https://lists.launchpad.net/openstack/msg23198.html
    # this treat includes secirity problem, but unfortunatly it is needed for quantum now.
    # when you noticed that it is not needed, please comment out these 2 lines.
    cp $BASE_DIR/conf/etc.sudoers.d/quantum_sudoers /etc/sudoers.d/quantum_sudoers
    chmod 440 /etc/sudoers.d/quantum_sudoers

    # restart processes
    cd /etc/init.d/; for i in $( ls quantum-* ); do sudo service $i restart; done
}

# --------------------------------------------------------------------------------------
# create network via quantum
# --------------------------------------------------------------------------------------
function create_network() {

    # check exist 'router-demo'
    ROUTER_CHECK=$(quantum router-list | grep "router-demo" | get_field 1)
    if [[ "$ROUTER_CHECK" == "" ]]; then
        echo "router does not exist." 
        # create internal network
        TENANT_ID=$(keystone tenant-list | grep " service " | get_field 1)
        INT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} int_net | grep ' id ' | get_field 2)
        # create internal sub network
        INT_SUBNET_ID=$(quantum subnet-create --tenant-id ${TENANT_ID} --ip_version 4 --gateway ${INT_NET_GATEWAY} ${INT_NET_ID} ${INT_NET_RANGE} | grep ' id ' | get_field 2)
        quantum subnet-update ${INT_SUBNET_ID} list=true --dns_nameservers 8.8.8.8 8.8.4.4
        # create internal router
        INT_ROUTER_ID=$(quantum router-create --tenant-id ${TENANT_ID} router-demo | grep ' id ' | get_field 2)
        INT_L3_AGENT_ID=$(quantum agent-list | grep ' L3 agent ' | get_field 1)
        while [[ "$INT_L3_AGENT_ID" = "" ]]
        do
            echo "waiting for L3 / DHCP agents..."
            sleep 3
            INT_L3_AGENT_ID=$(quantum agent-list | grep ' L3 agent ' | get_field 1)
        done
        #quantum l3-agent-router-add ${INT_L3_AGENT_ID} router-demo
        quantum router-interface-add ${INT_ROUTER_ID} ${INT_SUBNET_ID}
        # create external network
        EXT_NET_ID=$(quantum net-create --tenant-id ${TENANT_ID} ext_net -- --router:external=True | grep ' id ' | get_field 2)
        # create external sub network
        quantum subnet-create --tenant-id ${TENANT_ID} --gateway=${EXT_NET_GATEWAY} --allocation-pool start=${EXT_NET_START},end=${EXT_NET_END} ${EXT_NET_ID} ${EXT_NET_RANGE} -- --enable_dhcp=False
        # set external network to demo router
        quantum router-gateway-set ${INT_ROUTER_ID} ${EXT_NET_ID}
    else
        echo "router exist. You don't need to create network."
    fi
}

