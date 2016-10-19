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

