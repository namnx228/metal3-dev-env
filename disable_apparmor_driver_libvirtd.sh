foo="#security_driver = \"selinux\""
foo2="security_driver = \"apparmor\""
bar="security_driver = \"none\""
sudo sed -i "s/$foo/$bar/g" /etc/libvirt/qemu.conf
sudo sed -i "s/$foo2/$bar/g" /etc/libvirt/qemu.conf
sudo systemctl restart libvirtd 
sudo chmod o+rwx /var/run/libvirt/libvirt-sock

