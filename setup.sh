#!/usr/bin/env bash
#
# OpenStack Grizzly Installation Bash Script
#     allright reserved by Tomokazu Hirai @jedipunkz
#
# --------------------------------------------------------------------------------------
# Usage : sudo ./deploy.sh <node_type>
#   node_type    : allinone | controller | network | compute
# --------------------------------------------------------------------------------------

set -ex

# --------------------------------------------------------------------------------------
# include functions
# --------------------------------------------------------------------------------------
source ./functions.sh
source ./common.sh
#source ./nova-network.sh
source ./quantum.sh

# --------------------------------------------------------------------------------------
# include paramters of conf file.
# --------------------------------------------------------------------------------------
# quantum.conf has some parameters which you can set. If you want to know about each
# meaning of parameters, please see README_parameters.md.
source ./setup.conf
    
# --------------------------------------------------------------------------------------
# check OS release version
# --------------------------------------------------------------------------------------
# notice : This script was tested on precise only. 13.04 raring has a problem which
# we use gre tunneling with openvswitch. So I recommend that you use precise.
CODENAME=$(check_codename)
if [[ $CODENAME != "precise" ]]; then
    echo "Warning: This script was tested on Ubuntu 12.04 LTS precise only."
    exit 1
fi

# --------------------------------------------------------------------------------------
# check your user id
# --------------------------------------------------------------------------------------
# This script need root user access on target node. If you have root user id, please
# execute with 'sudo' command.
if [[ $EUID -ne 0 ]]; then
    echo "Warning: This script was designed for root user."
    exit 1
fi

# --------------------------------------------------------------------------------------
# execute
# --------------------------------------------------------------------------------------

case "$1" in
    allinone)
        check_interface $HOST_IP allinone
        NOVA_IP=${HOST_IP};                     check_para ${NOVA_IP}
        CINDER_IP=${HOST_IP};                   check_para ${CINDER_IP}
        DB_IP=${HOST_IP};                       check_para ${DB_IP}
        KEYSTONE_IP=${HOST_IP};                 check_para ${KEYSTONE_IP}
        GLANCE_IP=${HOST_IP};                   check_para ${GLANCE_IP}
        QUANTUM_IP=${HOST_IP};                  check_para ${QUANTUM_IP}
        RABBIT_IP=${HOST_IP};                   check_para ${RABBIT_IP}
        CONTROLLER_NODE_PUB_IP=${HOST_PUB_IP};  check_para ${CONTROLLER_NODE_PUB_IP}
        CONTROLLER_NODE_IP=${HOST_IP};          check_para ${CONTROLLER_NODE_IP}
        shell_env allinone
        init
        mysql_setup
        keystone_setup quantum
        glance_setup
        os_add
        openvswitch_setup allinone
        allinone_quantum_setup
        allinone_nova_setup
        cinder_setup allinone
        horizon_setup
        create_network
        scgroup_allow allinone
        printf '\033[0;32m%s\033[0m\n' 'This script was completed. :D'
        printf '\033[0;34m%s\033[0m\n' 'You have done! Enjoy it. :)))))'
        ;;
    controller)
        check_interface $CONTROLLER_NODE_PUB_IP controller
        NOVA_IP=${CONTROLLER_NODE_IP};              check_para ${NOVA_IP}
        CINDER_IP=${CONTROLLER_NODE_IP};            check_para ${CINDER_IP}
        DB_IP=${CONTROLLER_NODE_IP};                check_para ${DB_IP}
        KEYSTONE_IP=${CONTROLLER_NODE_IP};          check_para ${KEYSTONE_IP}
        GLANCE_IP=${CONTROLLER_NODE_IP};            check_para ${GLANCE_IP}
        QUANTUM_IP=${CONTROLLER_NODE_IP};           check_para ${QUANTUM_IP}
        RABBIT_IP=${CONTROLLER_NODE_IP};            check_para ${RABBIT_IP}
        shell_env separate
        init
        mysql_setup
        keystone_setup quantum controller
        glance_setup
        os_add
        controller_quantum_setup
        controller_nova_setup
        cinder_setup controller
        horizon_setup
        scgroup_allow controller
        printf '\033[0;32m%s\033[0m\n' 'Setup for controller node has done. :D.'
        printf '\033[0;34m%s\033[0m\n' 'Next, login to network node and exec "sudo ./setup.sh network".'
        ;;
    network)
        check_interface $NETWORK_NODE_IP network
        NOVA_IP=${CONTROLLER_NODE_IP};     check_para ${NOVA_IP}
        CINDER_IP=${CONTROLLER_NODE_IP};   check_para ${CINDER_IP}
        DB_IP=${CONTROLLER_NODE_IP};       check_para ${DB_IP}
        KEYSTONE_IP=${CONTROLLER_NODE_IP}; check_para ${KEYSTONE_IP}
        GLANCE_IP=${CONTROLLER_NODE_IP};   check_para ${GLANCE_IP}
        QUANTUM_IP=${CONTROLLER_NODE_IP};  check_para ${QUANTUM_IP}
        RABBIT_IP=${CONTROLLER_NODE_IP};   check_para ${RABBIT_IP}
        shell_env separate
        init
        openvswitch_setup network
        network_quantum_setup
        create_network
        printf '\033[0;32m%s\033[0m\n' 'Setup for network node has done. :D'
        printf '\033[0;34m%s\033[0m\n' 'Next, login to compute node and exec "sudo ./setup.sh compute".'
        ;;
    compute)
        NOVA_IP=${CONTROLLER_NODE_IP};     check_para ${NOVA_IP}
        CINDER_IP=${CONTROLLER_NODE_IP};   check_para ${CINDER_IP}
        DB_IP=${CONTROLLER_NODE_IP};       check_para ${DB_IP}
        KEYSTONE_IP=${CONTROLLER_NODE_IP}; check_para ${KEYSTONE_IP}
        GLANCE_IP=${CONTROLLER_NODE_IP};   check_para ${GLANCE_IP}
        QUANTUM_IP=${CONTROLLER_NODE_IP};  check_para ${QUANTUM_IP}
        RABBIT_IP=${CONTROLLER_NODE_IP};   check_para ${RABBIT_IP}
        shell_env separate
        init
        compute_nova_setup
        printf '\033[0;32m%s\033[0m\n' 'Setup for compute node has done. :D'
        printf '\033[0;34m%s\033[0m\n' 'You have done! Enjoy it. :)))))'
        ;;
    *)
        print_syntax
        ;;
esac

exit 0
