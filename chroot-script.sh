#!/bin/bash
set -ex

# Reload package sources
apt-get update
# DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" dist-upgrade

# Set default locales to 'en_US.UTF-8'
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen

echo 'locales locales/default_environment_locale select en_US.UTF-8' | debconf-set-selections
dpkg-reconfigure -f noninteractive locales

# Install Python 3 for Home Assistant
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  python3 \
  python3-venv \
  python3-pip

# Create home assistant user
groupadd -f -r -g 1001 homeassistant
useradd -u 1001 -g 1001 -rm homeassistant

# Install Home Assistant
python3 -m venv /srv/homeassistant
chown -R homeassistant:homeassistant /srv/homeassistant
su homeassistant -s /bin/bash -c "source /srv/homeassistant/bin/activate && pip install --upgrade pip && pip3 install --no-cache-dir homeassistant==${HOME_ASSISTANT_VERSION}"
systemctl enable home-assistant@homeassistant.service

# Install all of Home Assistant dependencies
su homeassistant -s /bin/bash -c "source /srv/homeassistant/bin/activate && pip3 install --no-cache-dir -r https://github.com/home-assistant/home-assistant/blob/dev/requirements_all.txt"
su homeassistant -s /bin/bash -c "source /srv/homeassistant/bin/activate && pip3 install --no-cache-dir python-persistent-queue"

# Clean up Python caches
find /srv/homeassistant/lib/ | \
  grep -E "(__pycache__|\.pyc$)" | \
  xargs rm -rf

# Install mosquitto
apt-get install -y \
  mosquitto

# Install influxdb
wget -q "https://dl.influxdata.com/influxdb/releases/influxdb_${INFLUXDB_VERSION}_armhf.deb"
dpkg -i "influxdb_${INFLUXDB_VERSION}_armhf.deb"

# TODO: Rename host name?
# TODO: Rename user and password?

# Cleanup APT cache and lists
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
