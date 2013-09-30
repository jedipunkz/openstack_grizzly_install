source ./setup.conf

function clear() {
  clear_databases
  clear_bridges
  clear_cinder_volume
}

function clear_databases() {
  for i in keystone glance nova cinder quantum
  do 
    mysql -uroot -p${MYSQL_PASS} -e "drop database if exists $i;"    
  done
}

function clear_bridges() {
  for i in br-int br-eth1 br-ex 
  do
    sudo ovs-vsctl del-br $i 
  done  
}

function clear_cinder_volume() {
  sudo vgremove cinder-volumes
  sudo pvremove -ff $CINDER_VOLUME
  sudo losetup -d $CINDER_VOLUME
}

case "$1" in
    allinone)
      clear
      ;;
    controller)
      # not implemented yet
      ;;
    network)
      # not implemented yet
      ;;
    compute)
      # not implemented yet
      ;;
esac

exit 0
