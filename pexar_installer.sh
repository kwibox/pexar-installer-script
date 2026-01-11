#!/bin/bash
# Pexar 2K Photo Frame app installer script
# Author: Stephan Teelen
# Version: 1.1
# Release: 17/11/2024

# GLOBALS
SMALI="https://bitbucket.org/JesusFreke/smali/downloads/smali-2.5.2.jar"
BAKSMALI="https://bitbucket.org/JesusFreke/smali/downloads/baksmali-2.5.2.jar"

ADB="./adb"

usage () {
    cat << 'EOF'

Pexar APK-installer
version 1.1

App installer for Pexar 2K Photoframe by patching Android PackageManager.service to bypass
isSystemApp() check

Orginal bypass method found by Jonathan Schemoul (https://notes.jmsinfor.com/blog/post/admin/36430176e522)
Script by Stephan Teelen (Kwibox) (https://www.toolserver.nl)

See XDA posts https://xdaforums.com/t/can-t-install-any-apk-on-pexar-photorame-android-11-using-adb-error-doesn-t-make-sense.4757220/

Requirements: device must be connected and recognized by Android debug bridge
For building a patch the following programes must to installed and added to your PATH-env:
sha512sum, zip, unzip, wget and Java Runtime Environment (JRE)

Enable ABD access in Frameo settings -> About. Enable Beta Program first to make the toggle for ADB access visibile.

Usage: pexar_installer [options] <package.apk> | --no-install

Options:
    -a, --adb <adb>                Path to Android Debug Bridge executable, defaults to adb in current dir
    -p, --patch <services.jar>     Install using pre-build services.jar patch, if none given script will build one
    --no-install                   Don't install an app, only build patch

When using a pre-build patch, this script will verify the SHA512 checksum and device fingerprint found in <services.jar>.verify
This file is auto-generated when building a patch and needs to be in the same directory as the patched <services.jar>
EOF
}

build_patch () {
    echo "Creating temp folder and checking requirements..."
    type zip >/dev/null 2>&1 || { echo >&2 "zip not found in path, please make sure it's installed, aborting"; exit 1; }
    type unzip >/dev/null 2>&1 || { echo >&2 "unzip not found in path, please make sure it's installed, aborting"; exit 1; }
    type wget >/dev/null 2>&1 || { echo >&2 "wget not found in path, please make sure it's installed, aborting"; exit 1; }
    type sha512sum  >/dev/null 2>&1 || { echo >&2 "sha512sum not found in path, please make sure it's installed, aborting"; exit 1; }
    type java  >/dev/null 2>&1 || { echo >&2 "Java Runtime Environment (JRE) not found in path, please make sure it's installed, aborting"; exit 1; }

    mkdir -p tmp

    echo "Downloading smali.jar from ${SMALI}"
    wget -q --show-progress $SMALI -O tmp/smali.jar
    echo "Downloading baksmali.jar from ${SMALI}"
    wget -q --show-progress $BAKSMALI -O tmp/baksmali.jar

    echo "Pulling services.jar containing PackageManagerService... "
    $ADB pull /system/framework/services.jar tmp/services.jar

    echo "Extracting and disassembling .jar..."
    cd tmp
    unzip -o services.jar -d services_extracted
    java -jar baksmali.jar d services_extracted/classes.dex -o services_smali

    if grep -q "is not allow to install" services_smali/com/android/server/pm/PackageManagerService.smali; then
        echo "Restriction found, now patching..."
    else
        echo "This script is not compatible with your Android build, please report your issue to the author of this script. Aborting"
        exit 1
    fi
    BEGIN=$(grep -n "\.method private isSystemApp(Ljava/lang/String;)Z" services_smali/com/android/server/pm/PackageManagerService.smali | cut -d ":" -f 1)
    END=$(grep -n -A100 "\.method private isSystemApp(Ljava/lang/String;)Z" services_smali/com/android/server/pm/PackageManagerService.smali | grep "end method" | cut -d "-" -f 1)

    cd services_smali/com/android/server/pm/

    head -n $((BEGIN - 1)) PackageManagerService.smali > PackageManagerService_patched.smali
    cat >> PackageManagerService_patched.smali << 'EOF'
.method private isSystemApp(Ljava/lang/String;)Z
    .registers 2
    # PATCHED: Always return true to allow any app installation
    const/4 v0, 0x1
    return v0
.end method
EOF
    tail -n +$((END + 1)) PackageManagerService.smali >> PackageManagerService_patched.smali
    mv PackageManagerService_patched.smali PackageManagerService.smali

    echo "Patching complete: "
    grep -A5 "\.method private isSystemApp(Ljava/lang/String;)Z" PackageManagerService.smali

    echo "Assembling and packaging .jar..."
    cd ../../../../..
    java -jar smali.jar a services_smali -o classes.dex
    mkdir -p services_new
    cd services_new
    unzip ../services.jar
    cp ../classes.dex classes.dex
    zip -r ../services_patched.jar *
    cd ..

    echo "Please check the patched jar is smaller (important for space constraints)"
    ls -la services.jar services_patched.jar
    cd ..
    mv tmp/services_patched.jar services_patched.jar

    echo "Cleaning up temp folder..."
    rm -R tmp

    echo "Writing device fingerprint and SHA512-checksum to services_patched.jar.verify... "
    $ADB shell getprop ro.system.build.fingerprint > services_patched.jar.verify
    sha512sum -b services_patched.jar | cut -d " " -f 1 >> services_patched.jar.verify

    echo "Done! Created services_patched.jar and services_patched.jar.verify"

}

verify_patch () {
    echo "Verifying $PATCH ..."
    if [[ -f $PATCH.verify ]]; then
        readarray -t verify < $PATCH.verify
    else
        echo "Missing .verify file; not able to verify .jar, aborting"
        exit 1
    fi

    if [[ $BUILD == ${verify[0]} ]]; then
        if sha512sum -b $PATCH | grep -q "${verify[1]}"; then
            echo "Connected device has matching fingerprint and SHA512-checksum is valid, continuing... "
        else
            echo "Patch SHA512-checksum is invalid; your .jar file might be corrupt, aborting"
            exit 1
        fi

    else
        echo "Patch fingerprint doesn't match current connected device, aborting"
        exit 1
    fi
}
install_apk () {
    echo "Preparing device for patch... "
    $ADB shell mount -o remount,rw /

    echo "Stopping Android system server..."
    $ADB shell stop
    sleep 10s

    echo "Removing odex/vdex files (they'll be auto-regenerated on reboot)"
    $ADB shell rm -f /system/framework/oat/arm/services.odex
    $ADB shell rm -f /system/framework/oat/arm/services.vdex
    $ADB shell rm -f /system/framework/oat/arm64/services.odex
    $ADB shell rm -f /system/framework/oat/arm64/services.vdex
    $ADB shell rm -f /system/framework/services.jar.bprof
    $ADB shell rm -f /system/framework/services.jar.prof

    # Push patched jar to data partition first
    echo "Installing patch..."
    $ADB push services_patched.jar /data/local/tmp/services.jar
    # Copy to system framework
    echo "Ignore error messages of crashed applications; it's expected some 'Droids are a bit unhappy 'coz of our meddling :)"
    $ADB shell cp /data/local/tmp/services.jar /system/framework/services.jar
    $ADB shell rm -f /data/local/tmp/services.jar
    echo "Restarting Android system server..."
    $ADB shell start
    read -p "Wait until the Frameo-app shows again and press <ENTER> to install $PACKAGE to device "
    echo "Installing ${PACKAGE}..."
    if $ADB install $PACKAGE | tee /dev/tty | grep -q "Success"; then
        echo "Install complete, now rebooting device!"
        $ADB reboot
    else
        echo "Installation failed, see above for details. Run again using the -p option to skip building a patch"
        echo "TIP: if you pressed <ENTER> too soon, you'll get an error stating package service couldn't be found"
        echo "If the issue persists, please ask help at the XDA Forum (english) or at gathering.tweakers.net (dutch)"
    fi
}

main () {
    echo "Check if device is connected..."
    BUILD=$($ADB shell getprop ro.system.build.fingerprint)

    if [[ -n "$BUILD" ]]; then
        echo "Connected device fingerprint: $BUILD"
        if [[ -v NO_INSTALL ]]; then
            echo "Only building patch, no app installation"
            build_patch

        else
            if [[ -v PATCH ]]; then
                verify_patch

            else
                echo "No patch provided, building one..."
                build_patch

            fi
            install_apk
        fi

    else
        echo "No device connected using ADB; please verify ADB is enabled and device is connected, arborting"
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--adb)
      ADB="$2"
      shift
      shift
      ;;
    -p|--patch)
      PATCH="$2"
      shift
      shift
      ;;
    -h|--help)
      usage
      exit 1
      ;;
    --no-install)
      NO_INSTALL=1
      shift
      ;;
    -*|--*)
      echo "Invalid option $1, see usage below"
      usage
      exit 1
      ;;
    *)
      PACKAGE="$1"
      shift
      ;;
  esac
done

if [[ -v PATCH ]] && ! [[ -s $PATCH ]]; then
    echo "No valid file supplied for patch, see usage below"
    usage

elif [[ -v NO_INSTALL ]] && [[ -v PATCH ]]; then
    echo "Invalid combination of arguments: there is nothing to do, see usage below"
    usage

elif [[ -v PACKAGE ]] && [[ $PACKAGE != *.apk ]] && [[ $PACKAGE != *.apex ]] ; then
    echo "Package name not valid; only .apk and apex are accepted, see usage below"
    usage

elif [[ -v NO_INSTALL ]] || [[ -f $PACKAGE ]]; then

    if ($ADB version | grep -q "Android Debug Bridge version"); then
        main

    else
        echo "Could not run Android Debug Bridge executable, please provide valid path, see usage below"
        usage
    fi

else
    echo "Missing or invalid path for required package.apk, see usage below"
    usage
fi
