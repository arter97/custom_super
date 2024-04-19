#!/bin/bash

ADB=$(which adb)
adb() {
  $ADB $* </dev/null
}

set -xeo pipefail

ls prebuilt/ | while read f; do adb push prebuilt/$f /dev; adb shell chmod 755 /dev/$f; done
adb shell /dev/dmsetup remove_all
adb shell /dev/busybox blkdiscard /dev/block/by-name/super
pv out/super.raw | zstd -T0 --long -9 | $ADB shell "/dev/zstd -T0 --long -dc > /dev/block/by-name/super"
adb shell sync
