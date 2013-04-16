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
source ./common.sh
source ./nova-network.sh
source ./quantum.sh

# --------------------------------------------------------------------------------------
# check OS release version
# --------------------------------------------------------------------------------------
CODENAME=$(check_codename)
if [[ $CODENAME != "precise" ]]; then
    echo "This code was tested on precise only."
    exit 1
fi

# --------------------------------------------------------------------------------------
# include each paramters of conf file.
# --------------------------------------------------------------------------------------
if [[ "$2" = "quantum" ]]; then
    source ./quantum.conf
elif [[ "$2" = "nova-network" ]]; then
    source ./nova-network.conf
else
    echo "network type must be : quantum or nova-network."
    exit 1
fi

# --------------------------------------------------------------------------------------
# execute
# --------------------------------------------------------------------------------------

if [[ "$2" = "nova-network" ]]; then

    echo "nova-network mode is under construcntion."
    exit 1

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
