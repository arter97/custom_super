#/******************************************************************************
# *
# * Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# * All rights reserved.
# * Confidential and Proprietary - Qualcomm Technologies, Inc.
# *
# ******************************************************************************/
#!/bin/bash

mkdir -p aptxalsOverlay/res/values

cat > aptxalsOverlay/Android.mk <<'EOM1'
LOCAL_PATH:= $(call my-dir)
include $(CLEAR_VARS)
LOCAL_CERTIFICATE := platform
LOCAL_RESOURCE_DIR := $(LOCAL_PATH)/res
LOCAL_PACKAGE_NAME := aptxalsOverlay
LOCAL_SDK_VERSION := current
LOCAL_VENDOR_MODULE := true
include $(BUILD_RRO_PACKAGE)
EOM1

cat > aptxalsOverlay/AndroidManifest.xml <<'EOM2'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
                package="com.qualcomm.qtil.aptxalsOverlay">
                <uses-sdk android:targetSdkVersion="34" />
                <overlay android:targetPackage="com.qualcomm.qtil.aptxals"
                 android:priority="1" android:isStatic="true"/>
</manifest>
EOM2

cat > aptxalsOverlay/res/values/strings.xml <<'EOM5'
<?xml version="1.0" encoding="utf-8"?>
<!--
/******************************************************************************
 *
 * Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
 * All rights reserved.
 * Confidential and Proprietary - Qualcomm Technologies, Inc.
 *
 ******************************************************************************/
-->
<resources>
    <string name="a2dp_offload_enabled">true</string>
    <string name="spatializer_monitor_enabled">false</string>
    <string name="refresh_audio_profile_count_enabled">false</string>
</resources>
EOM5


cat > aptxalsOverlay/install.sh <<'EOM6'

if [ ! -d $ANDROID_PRODUCT_OUT ]; then
    echo "Missing Android build env. Exiting"
    exit
fi

RROAPPSRC="/vendor/overlay/aptxalsOverlay.apk"
RROAPPDST="/vendor/overlay/aptxalsOverlay/aptxalsOverlay.apk"
if [ ! -f $ANDROID_PRODUCT_OUT/$RROAPPSRC ]; then
    echo "File $ANDROID_PRODUCT_OUT/$RROAPPSRC doesn't exist. Build using 'mm'."
    echo "Exiting without installing"
    exit
fi

adb wait-for-device root
adb remount
adb push $ANDROID_PRODUCT_OUT/$RROAPPSRC $RROAPPDST
adb shell sync
EOM6

chmod +x aptxalsOverlay/install.sh
