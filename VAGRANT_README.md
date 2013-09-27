
To install OpenStack Grizzly in 'allinone' mode with Vagrant on your local
VM, please follow the instructions as bellow:

1. checkout the repository

        % git clone
git://github.com/mingjin/openstack_grizzly_install.git
        % cd openstack_grizzly_install
% cp setup.conf.samples/setup.conf.allinone.quantum setup.conf
        
2. Edit the following parameters in setup.conf:

        HOST_IP='192.168.33.10'
        HOST_PUB_IP='192.168.34.10'
        PUBLICNETWORK_NIC_NETWORK_NODE='eth2'

2. Perhaps, you need to change the box name in Vagrantfile as well, e.g.
   'precise'

        config.vm.box = "ubuntu-12.04.1-server-amd64"
        
3. start a new VM and ssh login

        % vagrant up && vagrant ssh
        
4. go to the '/openstack_grizzly_install' folder and invoke the
   following commands:

        % ./setup.sh allinone
