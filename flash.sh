#!/bin/bash

ADB=$(which adb)
adb() {
  $ADB $* </dev/null
}

set -xeo pipefail

adb shell umount /vendor /odm > /dev/null 2>&1 || true
adb shell 'echo 1048576 > /proc/sys/vm/dirty_background_bytes'
ls prebuilt/ | while read f; do adb push prebuilt/$f /dev; adb shell chmod 755 /dev/$f; done
if [ -z "$1" ]; then
  adb shell /dev/dmsetup remove_all
  TARGET=super
  FILE=out/super.raw
  DEST=/dev/block/by-name/$TARGET
else
  TARGET=${1}_a
  FILE=out/${1}.img
  DEST=/dev/block/mapper/$TARGET
fi
adb shell /dev/busybox blkdiscard $DEST
pv $FILE | zstd -T0 -1 | $ADB shell "/dev/zstd -T0 --long -dc > $DEST"
adb shell sync
