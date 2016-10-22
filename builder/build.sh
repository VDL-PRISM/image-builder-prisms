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

RASPBIAN_IMAGE_NAME="${RASPBIAN_VERSION}-raspbian-jessie-lite.img"
RASPBIAN_IMAGE_PATH="${BUILD_RESULT_PATH}/${RASPBIAN_IMAGE_NAME}"
RASPBIAN_IMAGE_ZIP_NAME="${RASPBIAN_VERSION}-raspbian-jessie-lite.zip"
RASPBIAN_IMAGE_PATH_ZIP="${BUILD_RESULT_PATH}/${RASPBIAN_IMAGE_ZIP}"

# Name of the sd-image
PRISMS_IMAGE_VERSION=${VERSION:="dirty"}
PRISMS_IMAGE_NAME="${PRISMS_IMAGE_VERSION}-prisms_${RASPBIAN_IMAGE_NAME}.img"
export PRISMS_IMAGE_VERSION

# Create build directory for assembling our image filesystem
rm -rf ${BUILD_PATH}
mkdir ${BUILD_PATH}

# Download Raspbian
if [ ! -f "${RASPBIAN_IMAGE_PATH}" ]; then
  wget -q -O "${RASPBIAN_IMAGE_PATH_ZIP}" "https://downloads.raspberrypi.org/raspbian_lite/images/${RASPBIAN_IMAGE_ZIP_NAME}"

  # Verify checksum of our root filesystem
  echo "${ASPBIAN_IMAGE_CHECKSUM} ${RASPBIAN_IMAGE_PATH_ZIP}" | sha1sum -c -

  # Extract Raspbian image
  unzip -p "${RASPBIAN_IMAGE_PATH_ZIP}" > "${RASPBIAN_IMAGE_PATH}"

  rm "${RASPBIAN_IMAGE_PATH_ZIP}"
fi

cp "${RASPBIAN_IMAGE_PATH}" "/${PRISMS_IMAGE_NAME}"

# TODO: Extend file system?

# Register qemu-arm with binfmt to ensure that binaries we use in the chroot
# are executed via qemu-arm
update-binfmts --enable qemu-arm

guestmount -a "/${PRISMS_IMAGE_NAME}" -m /dev/sda2:/ -m /dev/sda1:/boot "${BUILD_PATH}"

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

guestunmount "${BUILD_PATH}"

# ensure that the travis-ci user can access the sd-card image file
umask 0000

# compress image
zip "${BUILD_RESULT_PATH}/${PRISMS_IMAGE_NAME}.zip" "/${PRISMS_IMAGE_NAME}"
cd ${BUILD_RESULT_PATH} && sha256sum "${PRISMS_IMAGE_NAME}.zip" > "${PRISMS_IMAGE_NAME}.zip.sha256" && cd -

# test sd-image that we have built
# VERSION=${PRISMS_IMAGE_VERSION} rspec --format documentation --color ${BUILD_RESULT_PATH}/builder/test
