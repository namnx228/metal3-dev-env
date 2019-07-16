set -xe 
source lib/logging.sh
source lib/common.sh

if [ "$MANAGE_PRO_BRIDGE" == "y" ]; then
     # Adding an IP address in the libvirt definition for this network results in
     # dnsmasq being run, we don't want that as we have our own dnsmasq, so set
     # the IP address here
     IFCFG_PROVISIONING_FILE=/etc/netplan/provision-bridge.yaml
     IFCFG_PROVISIONING=$(cat << EOF
network:
  version: 2
  renderer: networkd
  bridges:
    provisioning:
      dhcp4: no
      addresses: [172.22.0.1/24] 
      interfaces: []
EOF
     )

     if [ ! -e $IFCFG_PROVISIONING_FILE ] ; then
       echo -e "$IFCFG_PROVISIONING" | sudo dd of=$IFCFG_PROVISIONING_FILE
       sudo netplan apply 
     fi
 
     # Need to pass the provision interface for bare metal
     IFCFG_PRO_IF=$(cat << EOF
ethernets:
    $PRO_IF:
       dhcp4: no
EOF
     )
     if [ "$PRO_IF" ]; then
         sudo sed -i -e "s/interfaces: \[\]/interfaces: [$PRO_IF]/g" $IFCFG_PROVISIONING_FILE 
         echo -e "$IFCFG_PRO_IF" | sudo dd of=$IFCFG_PROVISIONING_FILE offlag=append conv=notrunc
         sudo netplan apply
     fi
 fi
 
 if [ "$MANAGE_INT_BRIDGE" == "y" ]; then
     # Create the baremetal bridge
     IFCFG_BAREMETAL_FILE=/etc/netplan/baremetal-bridge.yaml
     IFCFG_BAREMETAL=$(cat << EOF
network:
  version: 2
  renderer: networkd
  bridges:
    baremetal:
      dhcp4: no
      addresses: [192.168.111.1/24] 
      interfaces: []
EOF
      )
     if [ ! -e $IFCFG_BAREMETAL_FILE ] ; then
         echo -e "$IFCFG_BAREMETAL" | sudo dd of=$IFCFG_BAREMETAL_FILE
         sudo netplan apply
     fi
 
     # Add the internal interface to it if requests, this may also be the interface providing
     # external access so we need to make sure we maintain dhcp config if its available
     IFCFG_INT_IF=$(cat << EOF

ethernets:
    $INT_IF:
       dhcp4: no
EOF
     )
     if [ "$INT_IF" ]; then
         sudo sed -i -e "s/interfaces: \[\]/interfaces: [$INT_IF]/g" $IFCFG_BAREMETAL_FILE 
         echo -e "$IFCFG_INT_IF" | sudo dd of=$IFCFG_BAREMETAL_FILE offlag=append conv=notrunc
         if sudo nmap --script broadcast-dhcp-discover -e $INT_IF | grep "IP Offered" ; then
             sudo sed -i -e "s/\(.*\)dhcp4: no/\1dhcp4: yes/" $IFCFG_BAREMETAL_FILE
             sudo systemctl restart network
         else
            sudo systemctl restart network
         fi
     fi
 fi
 
 # restart the libvirt network so it applies an ip to the bridge
 if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
     sudo virsh net-destroy baremetal
     sudo virsh net-start baremetal
     if [ "$INT_IF" ]; then #Need to bring UP the NIC after destroying the libvirt network
         sudo ifup $INT_IF
     fi
 fi
