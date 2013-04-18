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

#### cinder device

you need disk device for cinder like /dev/sdb1. if you do not have additional
disk device, you can partition the disk device by partitioner.(/dev/sda6) and
please set device name ${CINDER_VOLUME} on setup.conf

#### in all in one node mode

You need 2 NICs (management network, public network). You can run this script
via management network NIC. VM can access to the internet via public network
NIC (default : eth0, You can change device on setup.conf).

#### in separated nodes mode

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
connectivity when you run this script.

#### Get this script

git clone this script from github.

    % git clone git://github.com/jedipunkz/openstack_grizlly_install.git
    % cd openstack_grizzly_install

#### Edit parameters on setup.conf

There are many paramaters on setup.conf, but in 'allinone' mode, parameters
which you need to edit is such things.

    HOST_IP='10.200.10.10'
    HOST_PUB_IP='10.200.9.10'
    PUBLIC_NIC='eth0'

If you want to change other parameters such as DB password, admin password,
please change these.

#### Run script

Run this script, all of conpornents will be built.

    % sudo ./setup.sh allinone

That's all and You've done. :D Now you can access to Horizon
(http://${HOST_IP}/horizon/) with user 'demo', password 'demo'.

How to use on separated nodes mode
----

#### OS installation

Please make a partition such as /dev/sda6 for cinder volumes, if you do not
have a additional disk device. and install openssh-server only. and you should
3 nodes or more. (controller, network, compute) nodes.

#### Get this script

git clone this script from github on controller node.

    controller% git clone git://github.com/jedipunkz/openstack_grizlly_install.git
    controller% cd openstack_grizzly_install

#### Edit parameters on setup.conf

There are many paramaters on setup.conf, but in 'allinone' mode, parameters
which you need to edit is such things.

    CONTROLLER_NODE_IP='10.200.10.10'
    CONTROLLER_NODE_PUB_IP='10.200.9.10'
    NETWORK_NODE_IP='10.200.10.11'
    COMPUTE_NODE_IP='10.200.10.12'
    DATA_NIC_CONTROLLER='eth1'
    DATA_NIC_COMPUTE='eth1'
    PUBLIC_NIC='eth0'

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

    # for VM traffic to the internet
    auto eth1
    iface eth1 inet static
        address 172.16.1.10
        netmask 255.255.255.0

    # for management network
    auto eth2
    iface eth2 inet static
        address 10.200.10.10
        netmask 255.255.255.0
        dns-nameservers 8.8.8.8 8.8.4.4
        dns-search example.com

and login to controller node via eth0 (public network) for executing this script.
Other NIC will lost connectivity.

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

Using Metadata server with quantum
----

VM can get some informations from metadata server on controller node.
add a routing table to VM range network like this.

    controller% source ~/openstackrc # use admin user
    controller% quantum router-list  # get route-id
    controller% quantum port-list -- --device_id <router_id> --device_owner network:router_gateway # get router I/F addr
    controller% route add -net 172.24.17.0/24 gw <route_if_addr>

Version and Change log
----

* 2013/04/17 : version 0.1 : First release.

