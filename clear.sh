source ./setup.conf

function clear() {
  clear_databases
  reenable_tgt
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
    ovs-vsctl del-br $i 
  done  
}

function clear_cinder_volume() {
  vgremove cinder-volumes
  pvremove -ff $CINDER_VOLUME
  losetup -d $CINDER_VOLUME
}

function reenable_tgt() {
  start_service tgt
  mv /etc/init/tgt.conf.diabled /etc/init/tgt.conf
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
