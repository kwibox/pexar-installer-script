# pexar-installer-script

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

*I included a pre-built services_patched.jar based on my own Pexar 2K frame with build fingerprint Lexar/PX-110/dpf1106_mk_32:11/RP1A.200720.011/PF1106_V2.06_20250527:user/release-keys*
