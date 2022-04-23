# aapsa_makefile_generator

AAPSA is a make file generator for prebuilt system apps using the Android AOSP build system.

Both /system/app and /system/priv-app destinations are supported.

Usage:

       1. Place the APKs you want to install into source_apks/app -OR- source_apks/priv-app.

       2. Run setup.bash with the path to your AOSP build tree's packages/apps directory and the path to
       your device's make file.
       E.x. bash setup.bash /home/bob/source/aosp/packages/apps /home/bob/source/aosp/device/generic/arm64/mini_arm64.mk

       3. (Re)Build AOSP using the device you used in step 1.

       4. Install the generated system.img and see if it works!

There is support for autogenerating the needed /etc/permissions/*.xml XML file for APKs installed
to the /system/priv-app directory on Android 9+. You can also use a premade one. The generated XML file
will have all of the requested permissions granted by default.
Note: These XML files are required as APKs that don't have all of their permissions defined in one will
cause the generated system.img to fail to boot.

Further, there is also support for extracting native libraries from the APK. These libraries will
be installed along side the APK in the selected destination.
I.e. an ARM64-v8a libfoo.so from an com.example.bar.APK installed to /system/app
will be installed to /system/app/com.example.bar/libs/arm64-v8a/libfoo.so.

In the event there are native libraries for more than one processor variant for a given architecture,
the lowest common denominator for that architecture will be used.
I.e. If com.example.bar.APK contains native libraries for both armeabi and armeabi-v7a, then the
armeabi versions will be extracted and used during installation.

NOTE: The libraries are included as their own modules within the build system. As AOSP's build system
does not support CPU variants when determining when to include modules, only the overall architecture,
a choice must be made. The method used by this script is designed to include support for as many devices
as possible.
NOTE2: Currently, this choice is implemented for ARM architectures only.


WARNING: Below is a rant... It is not friendly. If you keep reading, prepare to be insulted. You have been warned.
































Rant: There is no benefit provided by this XML requirement to anyone, developers or users.
The original default in Android 8 and below was that any APK in /system/priv-app got the permissions
it asked for by default, the end-user could not revoke those permissions nor uninstall the app
(No, "disabling" the app does not count as an uninstall.), and that the system.img always booted.
The requirement in Android 9+ creates a situation where among other things:

    1. Installing an APK to /system/priv-app requires any additional* permissions to be defined in an XML
        file in /system/etc/permissions/. (Where "additional permissions" are defined by the AOSP framework
        library and can be different depending on changes to the build tree. Which means that it's impossible
        to know when an XML file is required under /system/etc/permissions without running the utility for
        generating them.) Failure to do so when required results in an UNBOOTABLE system.img. A fact that is
        officially documented! (See https://source.android.com/devices/tech/config/perms-allowlist )

    2. Installing an APK to /{vendor/product}/priv-app has the same consequences as 1.

    3. The utility to generate the needed XML files is *NOT* integrated into the AOSP build system. There is
        no command that can be used in Android.mk or Android.bp files to generate the needed XML files.
        The official documentation says that you must run the utility *after* you build the system image once.
        (See https://source.android.com/devices/tech/config/perms-allowlist )

    4. The official utility to generate the needed XML files *CANNOT* be run by AOSP's make files. (Android.mk
        or Android.bp.) Attempting to do so causes the AOSP build system to complain about forbidden PATH usage.
        As the utility attempts to start adb and uses python's PATH resolution to find the needed aapt binary.
        (See https://android.googlesource.com/platform/build/+/master/Changes.md#path_tools)

    5. The official utility to generate the needed XML files outputs it's results to the console instead of
        an output file defined on the command line. Due to the adb usage, the output cannot be used directly
        without manual cleanup.

    6. The official utility to generate the needed XML files due to 5, does not place it's output into the
        target output directory, despite it's requirement of a valid AOSP build tree to run at all.

    7.  The AOSP build system has no option to include the generated XML files as part of a prebuilt
        APK module. In addition, AOSP prebuilt modules can only contain one source file per module.
        This along with 6 means that a developer must manually create the file in the correct location.
        Or create a new product module as a prebuilt that must be manually kept in sync with the prebuilt APK.

    8. The official utility to generate the needed XML files grants all requested permissions by default.
        Although the developer may deny permissions, this must be done manually. The end user is still unable
        to grant or deny permissions to these apps.

    9. The official utility to generate the needed XML files still uses deprecated AOSP build system tags
        (ANDROID_PRODUCT_OUT and ANDROID_HOST_OUT) that break their detection of the AOSP build tree.

   As the defaults are to still provide the same result as Android 8 and below (when the proper XML files are
   provided), there is no additional benefit to the end-user. As the problems above are still present with
   Android 10+ there is a lot of additional work, for no benefit if the defaults are used, that is now
   required of developers. Worse, if the unthinkable happens, there is the potential that an end-user may
   wind up with an unbootable device that requires servicing to fix. (Someone help Google if they accidentally
   approve a broken system.img and push it as an OTA update...)

   The privapp_permissions.py file included in this repo is a modified version of the official one that
   attempts to correct some of these oversights.
