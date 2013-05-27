OpenStack Grizzly Installation Script
====

OpenStack Grizzly Installation Bash Script for Ubuntu Server 12.04 LTS.

Author
----

Tomokazu Hirai @jedipunkz

Twitter : <https://twitter.com/jedipunkz>
Blog    : <http://jedipunkz.github.io>

Notice
----

This script was tested ..

* all in one node with quantum
* separated nodes (controller node, network node, compute x n) with quantum
* GRE Tunnel

so, now I do not support separated nodes for each service (keystone, glance,
nova, etc...). If you want to do this with separated nodes mode, please tell
me for fork it.

Motivation
----

devstack is very usefull for me. I am using devstack for understanding
openstack, especially Quantum ! ;) but when I reboot devstack node, all of
openstack compornents was not booted. That is not good for me. and I wanted to
use Ubuntu Cloud Archive packages.

Require Environment
----

#### Cinder Device

If you want use REAL disk device for cinder such as /dev/sdb, please input disk
device name to $CINDER_VOLUME in setup.conf. If you do not have any additional
disk for cinder, you can use loopback device. So please input loopback device
name such as /dev/loop3.

#### In All in ne node mode

You need 2 NICs (management network, public network). You can run this script
via management network NIC. VM can access to the internet via public network
NIC (default : eth0, You can change device on setup.conf).

#### In separated nodes mode

You need 3 NICs for ..

* management network
* public network / API network (default: eth0)
* data network (default: eth1)

for more details, please see this doc. 

<http://docs.openstack.org/trunk/openstack-network/admin/content/app_demo_single_router.html>

Quantum was designed on 4 networks (public, data, managememt, api) so You can
3 NICs on separated nodes mode. API network and Public network can share same
network segment or you can separate these networks. This README's
configuration of the premise is sharing a segment with API and Public network
(default NIC : eth0).

How to use on All in One Node
----

#### Architecture

    +------------------- Public/API Network
    |
    +------------+
    |vm|vm|...   |
    +------------+
    | all in one |
    +------------+
    |     |      
    +-----)------------- Management/API Network
          |             
          +------------- Data Network

* all of compornetns are on same node.

#### OS installation

Please make a partition such as /dev/sda6 for cinder volumes, if you do not
have a additional disk device. and install openssh-server only.

#### Setup network interfaces

Please setup network interfaces just like this.

    % sudo ${EDITOR} /etc/network/interfaces
    auto lo
    iface lo inet loopback
    
    # this NIC will be used for VM traffic to the internet
    auto eth0
    iface eth0 inet static
        up ifconfig $IFACE 0.0.0.0 up
        up ip link set $IFACE promisc on
        down ip link set $IFACE promisc off
        down ifconfig $IFACE down
        address 10.200.9.10
        netmask 255.255.255.0
        dns-nameservers 8.8.8.8 8.8.4.4
        dns-search example.com

    # this NIC must be on management network
    auto eth1
    iface eth1 inet static
        address 10.200.10.10
        netmask 255.255.255.0
        gateway 10.200.10.1
        dns-nameservers 8.8.8.8 8.8.4.4

login and use this script via eth1 on management network. eth0 will be lost
connectivity when you run this script. and make sure hostname resolv at
/etc/hosts. in this sample, your host need resolv self fqdn in 10.200.10.10

#### Get this script

git clone this script from github.

    % git clone git://github.com/jedipunkz/openstack_grizzly_install.git
    % cd openstack_grizzly_install

#### Edit parameters on setup.conf

There are many paramaters on setup.conf, but in 'allinone' mode, parameters
which you need to edit is such things.

    HOST_IP='10.200.10.10'
    HOST_PUB_IP='10.200.9.10'
    PUBLICNETWORK_NIC='eth0'

If you want to change other parameters such as DB password, admin password,
please change these.

#### Run script

Run this script, all of conpornents will be built.

    % sudo ./setup.sh allinone

That's all and You've done. :D Now you can access to Horizon
(http://${HOST_IP}/horizon/) with user 'demo', password 'demo'.

How to use on separated nodes mode
----

#### Architecture

    +-------------+-------------+------------------------------ Public/API Network
    |             |             |             
    +-----------+ +-----------+ +-----------+ +-----------+ +-----------+
    |           | |           | |           | |vm|vm|..   | |vm|vm|..   |
    | controller| |  network  | |  network  | +-----------+ +-----------+
    |           | |           | | additional| |  compute  | |  compute  |
    |           | |           | |           | |           | | additional|
    +-----------+ +-----------+ +-----------+ +-----------+ +-----------+
    |             |     |       |     |       |     |       |
    +-------------+-----)-------+-----)-------+-----)-------)-- Management/API Network
                        |             |             |       |
                        +-------------+-------------+---------- Data Network

* minimum architecture : 3 nodes (controller node x 1, network node x 1, compute node x1)
* You can add some network nodes and compute nodes.
* additional network node(s) make you be able to have duplication of each agent
* additional compute node(s) make you be able to have more VMs.

#### OS installation

Please make a partition such as /dev/sda6 for cinder volumes, if you do not
have a additional disk device. and install openssh-server only. and you should
3 nodes or more. (controller, network, compute) nodes.

#### Get this script

git clone this script from github on controller node.

    controller% git clone git://github.com/jedipunkz/openstack_grizzly_install.git
    controller% cd openstack_grizzly_install

#### Edit parameters on setup.conf

There are many paramaters on setup.conf, but in 'allinone' mode, parameters
which you need to edit is such things.

    CONTROLLER_NODE_IP='10.200.10.10'
    CONTROLLER_NODE_PUB_IP='10.200.9.10'
    NETWORK_NODE_IP='10.200.10.11'
    COMPUTE_NODE_IP='10.200.10.12'
    DATANETWORK_NIC_NETWORK_NODE='eth1'
    DATANETWORK_NIC_COMPUTE_NODE='eth1'
    PUBLICNETWORK_NIC='eth0'

If you want to change other parameters such as DB password, admin password,
please change these.

#### copy to other nodes

copy directory to network node and compute node.

    controller% scp -r openstack_grizzly_install <network_node_ip>:~/
    controller% scp -r openstack_grizzly_install <compute_node_ip>:~/

#### Controller Node's network interfaces

Set up NICs for controller node.

    controller% sudo ${EDITOR} /etc/network/interfaces
    # The loopback network interface
    auto lo
    iface lo inet loopback
    
    # for API network
    auto eth0
    iface eth0 inet static
        address 10.200.9.10
        netmask 255.255.255.0
        gateway 10.200.9.1
        dns-nameservers 8.8.8.8 8.8.4.4
        dns-search example.com

    # for management network
    auto eth1
    iface eth1 inet static
        address 10.200.10.10
        netmask 255.255.255.0
        dns-nameservers 8.8.8.8 8.8.4.4
        dns-search example.com

and login to controller node via eth0 (public network) for executing this script.
Other NIC will lost connectivity. and make sure hostname resolv at
/etc/hosts. in this sample, your host need resolv self fqdn in 10.200.9.10

#### Network Node's network interfaces

Set up NICs for network node.

    network% sudo ${EDITOR} /etc/network/interfaces
    # The loopback network interface
    auto lo
    iface lo inet loopback
    
    # for API network
    auto eth0
    iface eth0 inet static
        up ifconfig $IFACE 0.0.0.0 up
        up ip link set $IFACE promisc on
        down ip link set $IFACE promisc off
        down ifconfig $IFACE down
        address 10.200.9.11
        netmask 255.255.255.0
        dns-nameservers 8.8.8.8 8.8.4.4
        dns-search example.com

    # for VM traffic to the internet
    auto eth1
    iface eth1 inet static
        address 172.16.1.11
        netmask 255.255.255.0

    # for management network
    auto eth2
    iface eth2 inet static
        address 10.200.10.11
        netmask 255.255.255.0
        gateway 10.200.10.1
        dns-nameservers 8.8.8.8 8.8.4.4
        dns-search example.com

and login to network node via eth2 (management network) for executing this
script. Other NIC will lost connectivity.

#### Compute Node's network interfaces

Set up NICs for network node.

    compute% sudo ${EDITOR} /etc/network/interfaces
    # The loopback network interface
    auto lo
    iface lo inet loopback
    
    # for VM traffic to the internet
    auto eth0
    iface eth0 inet static
        address 172.16.1.12
        netmask 255.255.255.0

    # for management network
    auto eth1
    iface eth1 inet static
        address 10.200.10.12
        netmask 255.255.255.0
        gateway 10.200.10.1
        dns-nameservers 8.8.8.8 8.8.4.4
        dns-search example.com

and login to compute node via eth2 (mangement network) for executing this
script. Other NIC will lost connectivity.

#### Run script

Run this script, all of conpornents will be built.

    controller% sudo ./setup.sh controller
    network   % sudo ./setup.sh network
    compute   % sudo ./setup.sh comupte

That's all and You've done. :D Now you can access to Horizon
(http://${CONTROLLER_NODE_PUB_IP}/horizon/) with user 'demo', password 'demo'.

#### Additional Compute Node

If you want to have additional compute node(s), please setup network
interfaces as noted before for compute node and execute these commands.

Edit setup.conf (COPUTE_NODE_IP parameter) and execute setup.sh.

    compute    % scp -r ~/openstack_grizzly_install <add_compute_node>:~/
    add_compute% cd openstack_grizzly_install
    add_compute% ${EDITOR} setup.conf
    COMPUTE_NODE_IP='<your additional compute node's ip>'
    add_compute% sudo ./setup.sh compute
    add_compute% sudo nova-manage service list # check nodes list

#### Additional Network Node

If you want to have additional network node(s), please setup network
interfaces as noted before for network node and execute these commands.

Edit setup.conf (NETWORK_NODE_IP parameter) and execute setup.sh.

    network    % scp -r ~/openstack_grizzly_install <add_network_node>:~/
    add_network% cd openstack_grizzly_install
    add_network% ${EDITOR} setup.conf
    NETWORK_NODE_IP='<your additional network node's ip>'
    add_network% sudo ./setup.sh network
    add_network% source ~/openstackrc
    add_network% quantum agent-list # check agent list

Parameters
----

These are Meaning of parameters.

* HOST_IP : IP addr on management network with 'allinone' node
* HOST_PUB_IP : IP addr on public network with 'allinone' node
* PUBLIC_NIC : NIC name on public network with 'allinone' node
* CONTROLLER_NODE_IP : IP addr on management network with controller node
* CONTROLLER_NODE_PUB_IP : IP addr on public network with controller node
* NETWORK_NODE_IP : IP addr on management network with network node
* COMPUTE_NODE_IP : IP addr on management network with compute node
* DATA_NIC_CONTROLLER : NIC name on data network with controller node
* DATA_NIC_COMPUTE : NIC name on data network with compute nod
* PUBLIC_NIC : NIC name on public network on network node
* CINDER_VOLUME : Disk device name for Cinder Volume
* MYSQL_PASS : root password of MySQL
* DB_KEYSTONE_USER : MySQL user for Keystone
* DB_KEYSTONE_PASS : MySQL password for Keystone
* DB_GLANCE_USER : MySQL user for Glance
* DB_GLANCEPASS : MySQL password for Glance
* DB_QUANTUM_USER : MySQL user for Quantum
* DB_QUANTUM_PASS : MySQL password for Quantum
* DB_NOVA_USER : MySQL user for Nova
* DB_NOVA_PASS : MySQL password for Nova
* DB_CINDER_USER : MySQL user for Cinder
* DB_CINDER_PASS : MySQL password for CInder
* ADMIN_PASSWORD : Keystone password for admin user
* SERVICE_PASSWORD : Keystone password for service user
* OS_TENANT_NAME : OS tenant name
* OS_USERNAME : OS username
* OS_PASSWORD : OS password
* DEMO_USER : first user for DEMO
* DEMO_PASSWORD : first user's password for DEMO
* INT_NET_GATEWAY : Gateway address of internal network 
* INT_NET_RANGE : Range of external network
* EXT_NET_GATEWAY : Gateway address of external network
* EXT_NET_START : Starging address of external network
* EXT_NET_END : Ending address of external network
* EXT_NET_RANGE : Range of external network
* OS_IMAGE_URL : URL for downloading OS image file
* OS_IMAGE_NAME : Name of OS IMAGE name for Glance service

Licensing
----

This Script  is licensed under a Creative Commons Attribution 3.0 Unported License.

To view a copy of this license, visit
[ http://creativecommons.org/licenses/by/3.0/deed.en_US ].

Credits
----

This work has been based on: mseknibilel's guide.

<https://github.com/mseknibilel/OpenStack-Grizzly-Install-Guide>

Version and Change log
----

* 2013/05/27 : version 0.5 : supported vlan mode
* 2013/05/24 : version 0.4 : enabled to use loopback device for cinder.
* 2013/05/13 : version 0.3 : enabled nova live-migration
* 2013/04/18 : version 0.2 : enabled LBaaS, fixed a problem to access metadata server from vm.
* 2013/04/17 : version 0.1 : First release.

