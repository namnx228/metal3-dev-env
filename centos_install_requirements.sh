#!/usr/bin/env bash
set -ex

source lib/logging.sh
source lib/common.sh

sudo yum install -y libselinux-utils
if selinuxenabled ; then
    sudo setenforce permissive
    sudo sed -i "s/=enforcing/=permissive/g" /etc/selinux/config
fi

# Update to latest packages first
sudo yum -y update

# Install EPEL required by some packages
if [ ! -f /etc/yum.repos.d/epel.repo ] ; then
    if grep -q "Red Hat Enterprise Linux" /etc/redhat-release ; then
        sudo yum -y install http://mirror.centos.org/centos/7/extras/x86_64/Packages/epel-release-7-11.noarch.rpm
    else
        sudo yum -y install epel-release --enablerepo=extras
    fi
fi

# Install required packages
# python-{requests,setuptools} required for tripleo-repos install
sudo yum -y install \
  crudini \
  curl \
  dnsmasq \
  figlet \
  golang \
  NetworkManager \
  nmap \
  patch \
  psmisc \
  python-pip \
  python-requests \
  python-setuptools \
  vim-enhanced \
  wget

# We're reusing some tripleo pieces for this setup so clone them here
pushd $HOME
if [ ! -d tripleo-repos ]; then
  git clone https://git.openstack.org/openstack/tripleo-repos
fi
pushd tripleo-repos
sudo python setup.py install
popd
popd

# Needed to get a recent python-virtualbmc package
sudo tripleo-repos current-tripleo

# There are some packages which are newer in the tripleo repos
sudo yum -y update


# make sure additional requirments are installed
sudo yum -y install \
  ansible \
  bind-utils \
  jq \
  libguestfs-tools \
  nodejs \
  python-ironicclient \
  python-ironic-inspector-client \
  python-openstackclient \
  redhat-lsb-core \
  unzip \
  genisoimage

if [[ "${CONTAINER_RUNTIME}" == "podman" ]]; then
  sudo yum -y install podman
else
  sudo yum install -y yum-utils \
    device-mapper-persistent-data \
    lvm2
  sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
  sudo yum install -y docker-ce docker-ce-cli containerd.io
  sudo systemctl start docker
fi

# Install python packages not included as rpms
sudo pip install \
  lolcat \
  yq

