foo="#security_driver = \"selinux\""
foo2="security_driver = \"apparmor\""
bar="security_driver = \"none\""
sudo sed "s/$foo/$bar/g" /etc/libvirt/qemu.conf
sudo sed "s/$foo2/$bar/g" /etc/libvirt/qemu.conf
sudo systemctl restart libvirtd 
