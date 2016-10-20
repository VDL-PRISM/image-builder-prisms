#!/bin/bash -e
set -x
# This script should be run only inside of a Docker container
if [ ! -f /.dockerenv ]; then
  echo "ERROR: script works only in a Docker container!"
  exit 1
fi

# get versions for software that needs to be installed
source /workspace/versions.config

### setting up some important variables to control the build process

# place to store our created sd-image file
BUILD_RESULT_PATH="/workspace"

# place to build our sd-image
BUILD_PATH="/build"

# Show TRAVSI_TAG in travis builds
echo TRAVIS_TAG="${TRAVIS_TAG}"

# name of the sd-image we gonna create
PRISMS_IMAGE_VERSION=${VERSION:="dirty"}
PRISMS_IMAGE_NAME="prisms-rpi-${PRISMS_IMAGE_VERSION}.img"
export PRISMS_IMAGE_VERSION

http://director.downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2016-09-28/2016-09-23-raspbian-jessie-lite.zip

RASPBIAN_IMAGE="raspbian_lite-${RASPBIAN_VERSION}.img"
RASPBIAN_IMAGE_PATH="${BUILD_RESULT_PATH}/${RASPBIAN_IMAGE}"
RASPBIAN_IMAGE_ZIP="${RASPBIAN_IMAGE}.zip"
RASPBIAN_IMAGE_PATH_ZIP="${BUILD_RESULT_PATH}/${RASPBIAN_IMAGE_ZIP}"

# create build directory for assembling our image filesystem
rm -rf ${BUILD_PATH}
mkdir ${BUILD_PATH}

# download HypriotOS
if [ ! -f "${RASPBIAN_IMAGE_PATH}" ]; then
  wget -q -O "${RASPBIAN_IMAGE_PATH_ZIP}" "http://director.downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-${RASPBIAN_VERSION}/${RASPBIAN_VERSION}-raspbian-jessie-lite.zip"

  # verify checksum of our root filesystem
  # echo "${HYPRIOT_IMAGE_CHECKSUM} ${RASPBIAN_IMAGE_PATH_ZIP}" | sha256sum -c -

  # extract HypriotOS image
  unzip -p "${RASPBIAN_IMAGE_PATH_ZIP}" > "${RASPBIAN_IMAGE_PATH}"

  rm "${RASPBIAN_IMAGE_PATH_ZIP}"
fi

# extract parts of image
guestfish -a "${RASPBIAN_IMAGE_PATH}"<<_EOF_
  run
  #import filesystem content
  mount /dev/sda2 /
  tar-out / /image_root.tar.gz compress:gzip
  mount /dev/sda1 /boot
  tar-out /boot /image_boot.tar.gz compress:gzip
_EOF_

# untar file system to BUILD_PATH
tar -zxf image_root.tar.gz -C ${BUILD_PATH}
tar -zxf image_boot.tar.gz -C ${BUILD_PATH}/boot/

# register qemu-arm with binfmt
# to ensure that binaries we use in the chroot
# are executed via qemu-arm
update-binfmts --enable qemu-arm

# set up mount points for the pseudo filesystems
mkdir -p ${BUILD_PATH}/{proc,sys,dev/pts}

mount -o bind /dev ${BUILD_PATH}/dev
mount -o bind /dev/pts ${BUILD_PATH}/dev/pts
mount -t proc none ${BUILD_PATH}/proc
mount -t sysfs none ${BUILD_PATH}/sys

# modify/add image files directly
cp -R /builder/files/* ${BUILD_PATH}/

# make our build directory the current root
# and install the Rasberry Pi firmware, kernel packages,
# docker tools and some customizations
chroot ${BUILD_PATH} /bin/bash < /builder/chroot-script.sh

# unmount pseudo filesystems
umount -l ${BUILD_PATH}/dev/pts
umount -l ${BUILD_PATH}/dev
umount -l ${BUILD_PATH}/proc
umount -l ${BUILD_PATH}/sys

# package image filesytem into two tarballs - one for bootfs and one for rootfs
# ensure that there are no leftover artifacts in the pseudo filesystems
rm -rf ${BUILD_PATH}/{dev,sys,proc}/*

tar -czf /image_with_kernel_boot.tar.gz -C ${BUILD_PATH}/boot .
du -sh ${BUILD_PATH}/boot
rm -Rf ${BUILD_PATH}/boot
tar -czf /image_with_kernel_root.tar.gz -C ${BUILD_PATH} .
du -sh ${BUILD_PATH}
ls -alh /image_with_kernel_*.tar.gz

# download the ready-made raw image for the RPi
if [ ! -f "${BUILD_RESULT_PATH}/${RAW_IMAGE}.zip" ]; then
  wget -q -O "${BUILD_RESULT_PATH}/${RAW_IMAGE}.zip" "https://github.com/hypriot/image-builder-raw/releases/download/${RAW_IMAGE_VERSION}/${RAW_IMAGE}.zip"
fi

# # verify checksum of the ready-made raw image
echo "${RAW_IMAGE_CHECKSUM} ${BUILD_RESULT_PATH}/${RAW_IMAGE}.zip" | sha256sum -c -

unzip -p "${BUILD_RESULT_PATH}/${RAW_IMAGE}" > "/${PRISMS_IMAGE_NAME}"

# Since we added more stuff, we need to extend the file system
truncate -r "/${PRISMS_IMAGE_NAME}" "/new-${PRISMS_IMAGE_NAME}"
truncate -s +1G "/new-${PRISMS_IMAGE_NAME}"
virt-resize --expand /dev/sda2 "/${PRISMS_IMAGE_NAME}" "/new-${PRISMS_IMAGE_NAME}"
mv "/new-${PRISMS_IMAGE_NAME}" "/${PRISMS_IMAGE_NAME}"
ls -alh "/${PRISMS_IMAGE_NAME}"

# create the image and add root base filesystem
guestfish -a "/${PRISMS_IMAGE_NAME}"<<_EOF_
  run
  #import filesystem content
  mount /dev/sda2 /
  tar-in /image_with_kernel_root.tar.gz / compress:gzip
  mkdir /boot
  mount /dev/sda1 /boot
  tar-in /image_with_kernel_boot.tar.gz /boot compress:gzip
_EOF_

# ensure that the travis-ci user can access the sd-card image file
umask 0000

# compress image
zip "${BUILD_RESULT_PATH}/${PRISMS_IMAGE_NAME}.zip" "${PRISMS_IMAGE_NAME}"
cd ${BUILD_RESULT_PATH} && sha256sum "${PRISMS_IMAGE_NAME}.zip" > "${PRISMS_IMAGE_NAME}.zip.sha256" && cd -

# test sd-image that we have built
VERSION=${PRISMS_IMAGE_VERSION} rspec --format documentation --color ${BUILD_RESULT_PATH}/builder/test
