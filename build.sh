#!/bin/bash -e
set -x

# get versions for software that needs to be installed
source versions.config

### setting up some important variables to control the build process

# place to store our created sd-image file
BUILD_RESULT_PATH="${HOME}/images"

# place to build our sd-image
BUILD_PATH="${HOME}/build"

# Show TRAVSI_TAG in travis builds
echo TRAVIS_TAG="${TRAVIS_TAG}"

RASPBIAN_IMAGE_NAME="${RASPBIAN_VERSION}-raspbian-jessie-lite.img"
RASPBIAN_IMAGE_PATH="${BUILD_RESULT_PATH}/${RASPBIAN_IMAGE_NAME}"
RASPBIAN_IMAGE_ZIP="${RASPBIAN_VERSION}-raspbian-jessie-lite.zip"
RASPBIAN_IMAGE_PATH_ZIP="${BUILD_RESULT_PATH}/${RASPBIAN_IMAGE_ZIP}"

PRISMS_IMAGE_VERSION=${VERSION:="dirty"}
PRISMS_IMAGE_NAME="prisms-${PRISMS_IMAGE_VERSION}_${RASPBIAN_IMAGE_NAME}"
PRISMS_IMAGE_PATH="${BUILD_RESULT_PATH}/${PRISMS_IMAGE_NAME}"
export PRISMS_IMAGE_VERSION

# Install dependencies
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  zip \
  unzip \
  qemu \
  qemu-user-static \
  binfmt-support

if [ ! -d "${BUILD_RESULT_PATH}" ]; then
  mkdir ${BUILD_RESULT_PATH}
fi

# download Raspbian
if [ ! -f "${RASPBIAN_IMAGE_PATH}" ]; then
  # TODO: Fix this
  wget -q -O "${RASPBIAN_IMAGE_PATH_ZIP}" "http://director.downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-${RASPBIAN_FOLDER}/${RASPBIAN_VERSION}-raspbian-jessie-lite.zip"

  # Verify checksum of Raspbian
  echo "${RASPBIAN_CHECKSUM} ${RASPBIAN_IMAGE_PATH_ZIP}" | sha1sum -c -

  # extract Raspbian image
  unzip -p "${RASPBIAN_IMAGE_PATH_ZIP}" > "${RASPBIAN_IMAGE_PATH}"

  rm "${RASPBIAN_IMAGE_PATH_ZIP}"
fi

cp "${RASPBIAN_IMAGE_PATH}" "${PRISMS_IMAGE_PATH}"

# Make loopback devices
kpartx -a "${PRISMS_IMAGE_PATH}"

# Wait some time for changes to be made
sleep 5

# Create build directory for assembling the filesystem
rm -rf ${BUILD_PATH}
mkdir ${BUILD_PATH}

# Mount the image
mount /dev/mapper/loop0p2 -o rw ${BUILD_PATH}
mount /dev/mapper/loop0p1 -o rw ${BUILD_PATH}/boot

# Mount everything needed for the OS
mount --bind /dev ${BUILD_PATH}/dev/
mount --bind /sys ${BUILD_PATH}/sys/
mount --bind /proc ${BUILD_PATH}/proc/
mount --bind /dev/pts ${BUILD_PATH}/dev/pts

# Comment out every line in file
sed -i 's/^/# /' ${BUILD_PATH}/etc/ld.so.preload

cp /usr/bin/qemu-arm-static ${BUILD_PATH}/usr/bin

# Modify/add image files directly
cp -R files/* ${BUILD_PATH}/

chroot ${BUILD_PATH} /bin/bash < chroot-script.sh

# Uncomment out every line in file
sed -i 's/^# //' ${BUILD_PATH}/etc/ld.so.preload

# Unmount everything needed for the OS
umount -l ${BUILD_PATH}/dev/pts
umount -l ${BUILD_PATH}/proc
umount -l ${BUILD_PATH}/sys
umount -l ${BUILD_PATH}/dev

# Unmount the image
umount -l ${BUILD_PATH}/boot
umount -l ${BUILD_PATH}

sync
sleep 10

# Delete loopback devices
kpartx -d "${PRISMS_IMAGE_PATH}"

# Ensure that the travis-ci user can access the sd-card image file
umask 0000

# Compress image
zip -j "${BUILD_RESULT_PATH}/${PRISMS_IMAGE_NAME}.zip" "${PRISMS_IMAGE_PATH}"
cd ${BUILD_RESULT_PATH} && sha256sum "${PRISMS_IMAGE_NAME}.zip" > "${PRISMS_IMAGE_NAME}.zip.sha256" && cd -

# Test sd-image that we have built
# VERSION=${PRISMS_IMAGE_VERSION} rspec --format documentation --color ${BUILD_RESULT_PATH}/builder/test
