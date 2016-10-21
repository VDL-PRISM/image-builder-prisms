#!/bin/bash -e
set -x

# get versions for software that needs to be installed
source versions.config

### setting up some important variables to control the build process

# place to store our created sd-image file
BUILD_RESULT_PATH="~/images"

# place to build our sd-image
BUILD_PATH="~/build"

# Show TRAVSI_TAG in travis builds
echo TRAVIS_TAG="${TRAVIS_TAG}"

RASPBIAN_IMAGE="${RASPBIAN_VERSION}-raspbian-jessie-lite.img"
RASPBIAN_IMAGE_PATH="${BUILD_RESULT_PATH}/${RASPBIAN_IMAGE}"
RASPBIAN_IMAGE_ZIP="${RASPBIAN_VERSION}-raspbian-jessie-lite.zip"
RASPBIAN_IMAGE_PATH_ZIP="${BUILD_RESULT_PATH}/${RASPBIAN_IMAGE_ZIP}"

PRISMS_IMAGE_VERSION=${VERSION:="dirty"}
PRISMS_IMAGE_NAME="prisms-${PRISMS_IMAGE_VERSION}_${RASPBIAN_IMAGE}"
export PRISMS_IMAGE_VERSION

if [ ! -d "${BUILD_RESULT_PATH}" ]; then
  mkdir ${BUILD_RESULT_PATH}
fi

# download Raspbian
if [ ! -f "${RASPBIAN_IMAGE_PATH}" ]; then
  # TODO: Fix this
  wget -q -O "${RASPBIAN_IMAGE_PATH_ZIP}" "http://director.downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-${RASPBIAN_FOLDER}/${RASPBIAN_VERSION}-raspbian-jessie-lite.zip"

  # TODO: Check
  # verify checksum of our root filesystem
  # echo "${HYPRIOT_IMAGE_CHECKSUM} ${RASPBIAN_IMAGE_PATH_ZIP}" | sha256sum -c -

  # extract Raspbian image
  unzip -p "${RASPBIAN_IMAGE_PATH_ZIP}" > "${RASPBIAN_IMAGE_PATH}"

  rm "${RASPBIAN_IMAGE_PATH_ZIP}"
fi

cp "${RASPBIAN_IMAGE_PATH}" "${PRISMS_IMAGE_NAME}"

# Make loopback devices
losetup -f -P --show "${PRISMS_IMAGE_NAME}"

# create build directory for assembling our image filesystem
rm -rf ${BUILD_PATH}
mkdir ${BUILD_PATH}

mount /dev/loop0p2 -o rw ${BUILD_PATH}
mount /dev/loop0p1 -o rw ${BUILD_PATH}/boot

mount --bind /dev ${BUILD_PATH}/dev/
mount --bind /sys ${BUILD_PATH}/sys/
mount --bind /proc ${BUILD_PATH}/proc/
mount --bind /dev/pts ${BUILD_PATH}/dev/pts

# Comment out every line in file
sed -i 's/^/# /' ${BUILD_PATH}/etc/ld.so.preload

cp /usr/bin/qemu-arm-static ${BUILD_PATH}/usr/bin

# modify/add image files directly
cp -R /builder/files/* ${BUILD_PATH}/

# make our build directory the current root
# and install the Rasberry Pi firmware, kernel packages,
# docker tools and some customizations
chroot ${BUILD_PATH} /bin/bash < /builder/chroot-script.sh

# Uncomment out every line in file
sed -i 's/^# //' ${BUILD_PATH}/etc/ld.so.preload

umount ${BUILD_PATH}/dev
umount ${BUILD_PATH}/sys
umount ${BUILD_PATH}/proc
umount ${BUILD_PATH}/dev/pts
umount ${BUILD_PATH}/boot
umount ${BUILD_PATH}

losetup -d "${PRISMS_IMAGE_NAME}"

# ensure that the travis-ci user can access the sd-card image file
umask 0000

# compress image
zip "${BUILD_RESULT_PATH}/${PRISMS_IMAGE_NAME}.zip" "${PRISMS_IMAGE_NAME}"
cd ${BUILD_RESULT_PATH} && sha256sum "${PRISMS_IMAGE_NAME}.zip" > "${PRISMS_IMAGE_NAME}.zip.sha256" && cd -

# test sd-image that we have built
# VERSION=${PRISMS_IMAGE_VERSION} rspec --format documentation --color ${BUILD_RESULT_PATH}/builder/test
