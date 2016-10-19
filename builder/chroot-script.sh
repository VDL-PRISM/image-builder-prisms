#!/bin/bash
set -ex

# reload package sources
apt-get update
apt-get upgrade -y

# Install Python 3 for Home Assistant
apt-get install -y \
  python3 \
  python3-venv \
  python3-pip

# TODO: Install mosquitto
# TODO: Rename host name?
# TODO: Rename user?

# cleanup APT cache and lists
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
