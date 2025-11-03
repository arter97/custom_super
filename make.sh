#!/bin/bash

cleanup_lo() {
  ( ( losetup | grep "$STOCK_FIRMWARE" | awk '{print $1}' ) || true ) | while read l; do losetup -d $l; done
}

cleanup() {
  umount */* 2>/dev/null || true
  rm -rf orig out .files
  cleanup_lo
}

set -eo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root" 1>&2
  exit
fi

ALIGN=$((4 * 1024 * 1024)) # 4 MiB

SUPER_SIZE=18350080000

ODM_SIZE=8
PRODUCT_SIZE=1700
SYSTEM_DLKM_SIZE=32
SYSTEM_EXT_SIZE=300
SYSTEM_SIZE=9200
VENDOR_DLKM_SIZE=100
VENDOR_SIZE=5000

ACTIVE_SLOT=a
INACTIVE_SLOT=b

STOCK_FIRMWARE=/home/arter97/android/samsung/firmware/s937n/S937NKSS3BYJ2/images/dyn

TMP=/tmp/$(uuidgen)

export MKE2FS_CONFIG=prebuilt/mke2fs.conf
MKFS="mkfs.ext4 \
  -b 4096 \
  -O ^has_journal \
  -E lazy_itable_init=0,lazy_journal_init=0,nodiscard \
  -F -m 0 -I 256"

AVB=../avb/avbtool.py
AVB_KEY=../avb/test/data/testkey_rsa4096_pub.pem

avb_get_orig_size() {
  RET=$($AVB info_image --image "$1" | grep '^Original image size:' | awk '{print $4}')
  if [ -z "$RET" ]; then
    echo $(stat -L -c%s "$1")
  else
    echo "$1 orig size = $RET" 1>&2
    echo $RET
  fi
}

#MOD=$( ( ls files; ( grep -o '^[^#]*' remove.txt || true ) | awk -F/ '{print $1}' ) | sort | uniq | tr '\n' ' ')
MOD="odm product system_dlkm system_ext system vendor_dlkm vendor"

cleanup

mkdir -p out orig
for f in "$STOCK_FIRMWARE/"*.raw; do
  ln -s $(losetup -f --show -b 4096 --sizelimit $(avb_get_orig_size "$f") "$f") out/$(basename $f)
done
for i in $MOD; do
  mkdir orig/$i out/$i
  mount -o ro out/$i.raw orig/$i

 (
  if grep -o '^[^#]*' remove.txt | grep -q "^$i/"; then
    TMP=/tmp/custom-super-$(uuidgen)
    grep -o '^[^#]*' remove.txt | grep "^$i/" | cut -c$((${#i} + 2))- > $TMP
    rsync -ahAXx --exclude-from $TMP --inplace --numeric-ids orig/$i/ out/$i/
    rm $TMP
  else
    rsync -ahAXx --inplace --numeric-ids orig/$i/ out/$i/
  fi
  echo "Copying $i done"
 ) &
done

wait

echo "Adding files"
rsync -ahAX --inplace --numeric-ids files/ .files/
cd .files/
# Restore recorded file attributes
setfacl -P --restore=../attr/acl.txt
setfattr -h --restore=../attr/xattr.txt
# Override them from stock attributes
LIST=$(find .)
( cd ../orig; getfacl -Pn $(ls -d $LIST 2>/dev/null) ) | setfacl -P --restore=-
( cd ../orig; getfattr -dhP -m- $(ls -d $LIST 2>/dev/null) ) | setfattr -h --restore=-
( find */ -exec ls -aldnZ {} + | grep '?' ) || true
cd ..
rsync -ahAX --inplace --numeric-ids .files/ out/
rm -rf .files

cd append
find -type f | while read f; do
  cat "$f" >> ../out/"$f"
done
cd ..

echo "Running custom plugins"
run-parts --exit-on-error -v plugins

echo "Unmounting"
for i in $MOD; do
  umount "orig/$i" &
done

wait

echo "Creating images"
for i in $MOD; do
 (
  eval SIZE='$'$(echo $i | tr '[:lower:]' '[:upper:]')_SIZE
  SIZE=$(($SIZE * 1024 * 1024))

  rm out/$i.raw
  fallocate -l $SIZE out/$i.img
  $MKFS -L $i -d out/$i out/$i.img

  echo Created $i: original size = $(du -sh --apparent-size "$STOCK_FIRMWARE/$i.raw" | awk '{print $1}'), new size = $(du -sh --apparent-size "out/$i.img" | awk '{print $1}')
 ) &
done

wait

echo "Creating super.img"
# Create argument list
ARG=""
while read img; do
  PART_NAME=$(echo $img | sed -e 's/\.img//g' -e 's/\.raw//g')
  eval SIZE='$'$(echo $PART_NAME | tr '[:lower:]' '[:upper:]')_SIZE
  SIZE=$(($SIZE * 1024 * 1024))
  ARG="$ARG -p ${PART_NAME}_${INACTIVE_SLOT}:none:0:qti_dynamic_partitions_${INACTIVE_SLOT}"
  ARG="$ARG -p ${PART_NAME}_${ACTIVE_SLOT}:none:${SIZE}:qti_dynamic_partitions_${ACTIVE_SLOT} -i ${PART_NAME}_${ACTIVE_SLOT}=out/$img"
done < <(ls out/ | grep -E '\.img$|\.raw$')

set -x
lpmake \
    -d $SUPER_SIZE \
    --metadata-size=65536 \
    --metadata-slots=3 \
    --alignment=$ALIGN \
    --alignment-offset=$ALIGN \
    --super-name=super \
    --virtual-ab \
    -o out/super.raw \
    -g qti_dynamic_partitions_${INACTIVE_SLOT}:$(($SUPER_SIZE - $ALIGN)) \
    -g qti_dynamic_partitions_${ACTIVE_SLOT}:$(($SUPER_SIZE - $ALIGN)) \
    $ARG
set +x
cleanup_lo

ls -al out/super.raw
