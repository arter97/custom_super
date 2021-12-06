#!/bin/bash

set -eo pipefail

LPMAKE=/mnt/out/par/host/linux-x86/bin/lpmake
ALIGN=$((4 * 1024 * 1024)) # 4 MiB

SUPER_SIZE=11190403072
SYSTEM_SIZE=2147483648
SYSTEM_EXT_SIZE=1433104384
PRODUCT_SIZE=1073741824
VENDOR_SIZE=2684354560
# odm is copied without modification

ACTIVE_SLOT=a
INACTIVE_SLOT=b

STOCK_FIRMWARE=/home/arter97/Downloads/op9/out
OUT=new

TMP=/tmp/$(uuidgen)

MKFS="mkfs.ext4 \
  -b 4096 \
  -O ^has_journal \
  -E lazy_itable_init=0,lazy_journal_init=0,nodiscard \
  -F -m 0"

mkdir -p $OUT
for i in system system_ext product vendor; do
  echo "Creating $i.img"
  eval SIZE='$'$(echo $i | tr '[:lower:]' '[:upper:]')_SIZE
  fallocate -l $SIZE $OUT/$i.img
  $MKFS $OUT/$i.img
  mkdir -p orig/$i $OUT/$i
  mount -t ext4 -o ro "$STOCK_FIRMWARE/$i.img" orig/$i
  mount -t ext4 $OUT/$i.img $OUT/$i

  echo "Copying $i data"
  if cat remove.txt | grep -q "^$i/"; then
    cat remove.txt | grep "^$i/" | cut -c$((${#i} + 2))- > $TMP
    rsync -ahAXx --exclude-from $TMP --inplace --numeric-ids orig/$i/ $OUT/$i/
  else
    rsync -ahAXx --inplace --numeric-ids orig/$i/ $OUT/$i/
  fi
done

echo "Adding files"
./restore.sh
rsync -ahAX --inplace --numeric-ids files/ $OUT/

echo "Patching files"
find patches/ -type f | cut -c9- | while read f; do
  getfacl -Pn "$OUT/$f" > ${TMP}.acl
  getfattr -dhP -m- "$OUT/$f" > ${TMP}.xattr
  patch --no-backup-if-mismatch -r - "$OUT/$f" < "patches/$f"
  setfacl -P --restore=${TMP}.acl
  setfattr -h --restore=${TMP}.xattr
done
rm ${TMP}.acl ${TMP}.xattr

echo "Unmounting"
for i in system system_ext product vendor; do
  umount "$OUT/$i"
  umount "orig/$i"
done

echo "Creating super.img"
$LPMAKE \
    -d $SUPER_SIZE \
    --metadata-size=65536 \
    --metadata-slots=3 \
    --alignment=$ALIGN \
    --alignment-offset=$ALIGN \
    --super-name=super \
    --virtual-ab \
    --sparse \
    -o $OUT/super.img \
    -g qti_dynamic_partitions_${INACTIVE_SLOT}:$(($SUPER_SIZE - $ALIGN)) \
    -g qti_dynamic_partitions_${ACTIVE_SLOT}:$(($SUPER_SIZE - $ALIGN)) \
    -p system_${INACTIVE_SLOT}:none:0:qti_dynamic_partitions_${INACTIVE_SLOT} \
    -p system_${ACTIVE_SLOT}:none:${SYSTEM_SIZE}:qti_dynamic_partitions_${ACTIVE_SLOT} \
    -i system_${ACTIVE_SLOT}="$OUT/"system.img \
    -p system_ext_${INACTIVE_SLOT}:none:0:qti_dynamic_partitions_${INACTIVE_SLOT} \
    -p system_ext_${ACTIVE_SLOT}:none:${SYSTEM_EXT_SIZE}:qti_dynamic_partitions_${ACTIVE_SLOT} \
    -i system_ext_${ACTIVE_SLOT}="$OUT/"system_ext.img \
    -p product_${INACTIVE_SLOT}:none:0:qti_dynamic_partitions_${INACTIVE_SLOT} \
    -p product_${ACTIVE_SLOT}:none:${PRODUCT_SIZE}:qti_dynamic_partitions_${ACTIVE_SLOT} \
    -i product_${ACTIVE_SLOT}="$OUT/"product.img \
    -p vendor_${INACTIVE_SLOT}:none:0:qti_dynamic_partitions_${INACTIVE_SLOT} \
    -p vendor_${ACTIVE_SLOT}:none:${VENDOR_SIZE}:qti_dynamic_partitions_${ACTIVE_SLOT} \
    -i vendor_${ACTIVE_SLOT}="$OUT/"vendor.img \
    -p odm_${INACTIVE_SLOT}:none:0:qti_dynamic_partitions_${INACTIVE_SLOT} \
    -p odm_${ACTIVE_SLOT}:none:$(stat -c %s "$STOCK_FIRMWARE/odm.img"):qti_dynamic_partitions_${ACTIVE_SLOT} \
    -i odm_${ACTIVE_SLOT}="$STOCK_FIRMWARE/odm.img"

ls -al $OUT/super.img
