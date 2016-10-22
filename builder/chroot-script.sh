#!/bin/bash
set -ex

# Set default locales to 'en_US.UTF-8'
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen

echo 'locales locales/default_environment_locale select en_US.UTF-8' | debconf-set-selections
dpkg-reconfigure -f noninteractive locales

# reload package sources
apt-get update
apt-get upgrade -y

# Install Python 3 for Home Assistant
apt-get install -y \
  python3 \
  python3-venv \
  python3-pip

# Create home assistant user
groupadd -f -r -g 1001 homeassistant
useradd -u 1001 -g 1001 -rm homeassistant

# Install Home Assistant
python3 -m venv /srv/homeassistant
chown -R homeassistant:homeassistant /srv/homeassistant

su homeassistant -s /bin/bash <<EOF
source /srv/homeassistant/bin/activate
pip3 install --upgrade pip
pip3 install --no-cache-dir homeassistant==${HOME_ASSISTANT_VERSION}
# TODO: Install all of Home Assistant dependencies
# pip3 install --no-cache-dir -r https://raw.githubusercontent.com/home-assistant/home-assistant/dev/requirements_all.txt
EOF
systemctl enable home-assistant@homeassistant.service

# Clean up Python caches
find /srv/homeassistant/lib/ | \
  grep -E "(__pycache__|\.pyc$)" | \
  xargs rm -rf

# Install mosquitto
apt-get install -y \
  mosquitto

# Install influxdb
wget -q "https://dl.influxdata.com/influxdb/releases/influxdb_${INFLUXDB_VERSION}_armhf.deb"
sudo dpkg -i "influxdb_${INFLUXDB_VERSION}_armhf.deb"

# TODO: Rename host name?
# TODO: Rename user and password?

# Cleanup APT cache and lists
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
