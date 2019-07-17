#!/usr/bin/env bash
OS=$(uname -a)
if [[ $OS == *Ubuntu* ]]; then
  source ubuntu_install_requirements.sh
else
  source centos_install_requirements.sh
fi
