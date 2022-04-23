#!/bin/bash

# This script is for generating the main Android.mk make file for installing prebuilt
# APKs on the generated system partition.

function process_apk {
# Check args.
if [ $# -eq 3 ]; then
    if [ "$1" != "" ]; then
        echo "Processing APK ( $1 )...." >&2

        # Define vars.
        LOC_LIB_NAMES_LEN=0
        LOC_LIB_NAMES=""
        declare -a LOC_LIB_MK_FILES
        declare -i LOC_LIB_MK_FILES_IDX=0
        declare -a LOC_SONAME_ARR
        declare -i LOC_SONAME_ARR_IDX=0
        LOC_APK_FILE="$1"
        LOC_APK_FILE_LEN="${#1}"
        if [ "$3" != "" ]; then
            LOC_APK_NAME="$3"
            LOC_APK_NAME_LEN="${#3}"
            LOC_MAIN_MK_FILE="Android.mk"
            # Determine the APK's installation directory on the target.
            if [ "$2" == "priv-app" ]; then
                # Privileged app....
                LOC_INS_DIR_TARGET="\$(TARGET_OUT_APPS_PRIVILEGED)/$LOC_APK_NAME"
            else
                # Normal app....
                LOC_INS_DIR_TARGET="\$(TARGET_OUT_APPS)/$LOC_APK_NAME"
            fi
            EXTRACTED_LIB_FOLDER_TMP="extracted_libs"
            EXTRACTED_LIB_FOLDER="${EXTRACTED_LIB_FOLDER_TMP}/${LOC_APK_NAME}"
            retC=0

            # Extract the shared libs from the apk file....
            if [ -d "$EXTRACTED_LIB_FOLDER" ]; then
                rm -rf "$EXTRACTED_LIB_FOLDER"
                sync
            fi
            mkdir -p "$EXTRACTED_LIB_FOLDER"
            retC=$?
            if [ $retC -eq 0 ]; then
                if [ -f "${EXTRACTED_LIB_FOLDER_TMP}/Android.mk" ]; then
                    rm -f "${EXTRACTED_LIB_FOLDER_TMP}/Android.mk"
                fi
                echo 'MY_INTER0_LOCAL_PATH := $(call my-dir)' >> "${EXTRACTED_LIB_FOLDER_TMP}/Android.mk"
                echo 'LOCAL_PATH := $(MY_INTER0_LOCAL_PATH)' >> "${EXTRACTED_LIB_FOLDER_TMP}/Android.mk"
                echo 'include $(call all-subdir-makefiles)' >> "${EXTRACTED_LIB_FOLDER_TMP}/Android.mk"
                echo 'include $(CLEAR_VARS)' >> "${EXTRACTED_LIB_FOLDER_TMP}/Android.mk"
                echo 'LOCAL_PATH := $(MY_INTER0_LOCAL_PATH)' >> "${EXTRACTED_LIB_FOLDER_TMP}/Android.mk"

                unzip -d "$EXTRACTED_LIB_FOLDER" "$LOC_APK_FILE" 'lib*' &> /dev/null
                retC=$?
                if [ $retC -eq 0 ]; then
                    # Enter extracted lib folder.
                    pushd "$EXTRACTED_LIB_FOLDER" &> /dev/null
                    retC=$?
                    if [ $retC -eq 0 ]; then
                        # Create the make files for the shared libs....
                        "$NATIVE_LIB_SCRIPT" "$LOC_INS_DIR_TARGET" "$LOC_APK_NAME"
                        retC=$?
                        if [ $retC -eq 0 ]; then
                            echo "ERROR: No native library make files were created for APK ( $LOC_APK_FILE ). Aborting." >&2
                            retC=-1
                        else
                            # Reset retC so we can continue below.
                            retC=0

                            STR_LIB_FILE="build-$LOC_APK_NAME-libnames.txt"
                            STR_LIB_LEN="${#i}"
                            if [ -f "$PWD/$STR_LIB_FILE" ]; then
                                LOC_LIB_NAMES=`cat "$PWD/$STR_LIB_FILE"`
                                LOC_LIB_NAMES_LEN=${#LOC_LIB_NAMES}
                                if [ $LOC_LIB_NAMES_LEN -le 0 ]; then
                                    echo "ERROR: ( $PWD/build-$LOC_APK_NAME-libnames.txt ) is empty. Aborting." >&2
                                    retC=-1
                                fi

                                # Create the LOC_SONAME_ARR.
                                declare -a TMP_SONAME_ARR
                                TMP_SONAME_ARR=(`cat "$PWD/$STR_LIB_FILE"`)
                                if [ ${#TMP_SONAME_ARR[@]} -gt 0 ]; then
                                    for a in "${TMP_SONAME_ARR[@]}"; do
                                        LOC_SONAME_ARR[$LOC_SONAME_ARR_IDX]="${a}.so"
                                        LOC_SONAME_ARR_IDX=$LOC_SONAME_ARR_IDX+1
                                    done
                                else
                                    echo "ERROR: Could not get listing of shared library SONAMES. Aborting." >&2
                                    retC=-1
                                fi
                                unset TMP_SONAME_ARR

                                # Get the names of the generated mk files to include into our main file.
                                for x in *.mk; do
                                    # Skip wildcard.
                                    if [ "$x" == "*.mk" ]; then
                                        continue
                                    else
                                        LOC_LIB_MK_FILES[$LOC_LIB_MK_FILES_IDX]="$x"
                                        LOC_LIB_MK_FILES_IDX=$LOC_LIB_MK_FILES_IDX+1
                                    fi
                                done

                                # Check if we need to include a list of shared library mk files.
                                if [ $LOC_LIB_MK_FILES_IDX -gt 0 ]; then
                                    if [ -f "${PWD}/Android.mk" ]; then
                                        rm -f "${PWD}/Android.mk"
                                    fi
                                    echo 'MY_INTER1_LOCAL_PATH := $(call my-dir)' >> "${PWD}/Android.mk"
                                    echo 'LOCAL_PATH := $(MY_INTER1_LOCAL_PATH)' >> "${PWD}/Android.mk"
                                    for i in "${LOC_LIB_MK_FILES[@]}"; do
                                        echo -n 'include $(LOCAL_PATH)/' >> "${PWD}/Android.mk"
                                        echo "${i}" >> "${PWD}/Android.mk"
                                    done
                                fi

                                if [ $LOC_LIB_MK_FILES_IDX -le 0 ]; then
                                    echo "ERROR: Could not get listing of generated shared library mk files. Aborting." >&2
                                    retC=-1
                                fi
                            else
                                echo "ERROR: ( $PWD/build-$LOC_APK_NAME-libnames.txt ) was NOT generated. Aborting." >&2
                                retC=-1
                            fi
                        fi
                        # Return to previous directory.
                        popd &> /dev/null
                    else
                        echo "ERROR: Unable to enter directory ( $EXTRACTED_LIB_FOLDER ). Aborting." >&2
                    fi
                    # Include the shared lib make files into the main make file below...
                else
                    if [ $retC -eq 11 ]; then
                        # There were no lib files to extract.
                        retC = 0
                        echo "INFO: unzip did not find any shared library files for the APK ( $LOC_APK_FILE )." >&2
                        rm -rf "$EXTRACTED_LIB_FOLDER"
                    else
                        echo "ERROR: unzip failed with error code ( $retC ) for APK ( $LOC_APK_FILE ). Aborting." >&2
                    fi
                fi
            else
                # Unable to create extracted lib folder.
                echo "ERROR: Unable to create extracted lib folder. ( $EXTRACTED_LIB_FOLDER ) Aborting." >&2
                retC=-1
            fi

            # Check if we should create the main Android.mk file.
            if [ $retC -eq 0 ]; then
                # Generate the initial main mk file.
                if [ -f "$LOC_MAIN_MK_FILE" ]; then
                    rm -f "$LOC_MAIN_MK_FILE"
                    sync
                fi
                # Cache the local path.
                echo 'MY_APP_LOCAL_PATH := $(call my-dir)' >> "$LOC_MAIN_MK_FILE"
                # Include the generated extracted lib make files. (If needed.)
                echo 'include $(call all-subdir-makefiles)' >> "$LOC_MAIN_MK_FILE"
                # Restore local path and vars after the extracted lib make files are processed.
                echo 'LOCAL_PATH := $(MY_APP_LOCAL_PATH)' >> "$LOC_MAIN_MK_FILE"
                echo 'include $(CLEAR_VARS)' >> "$LOC_MAIN_MK_FILE"
                echo '' >> "$LOC_MAIN_MK_FILE"

                # Generate the priv-app perms XML file if needed.
                if [ "$2" == "priv-app" ]; then
                    # Generate the priv-app perms XML file names.
                    GEND_XML_OUTPUT="${LOC_APK_NAME}_autogenerated_priv_app_permissions.xml"
                    TMP_XML_OUTPUT="${GEND_XML_OUTPUT}.temp"

                    # Generate the priv-app perms XML file make file module name.
                    PRIV_APP_XML_MOD_NAME="${LOC_APK_NAME}_priv-app_permissions_xml"

                    # Create a make file variable to detect if it needs to include the priv-app perms XML file.
                    echo 'MY_PRIV_APP_PERM_XML_MODULE := ' >> "$LOC_MAIN_MK_FILE"
                    echo '' >> "$LOC_MAIN_MK_FILE"

                    # Output the command to generate the priv-app permissions.xml
                    if [ $DEBUG_SCRIPT_ENABLED -gt 0 ]; then
                        echo '$(warning PRODUCT_OUT IS [$(PRODUCT_OUT)].)' >> "$LOC_MAIN_MK_FILE"
                        echo '$(warning HOST_OUT IS [$(HOST_OUT)].)' >> "$LOC_MAIN_MK_FILE"
                        echo '$(warning TOPDIR IS [$(TOPDIR)].)' >> "$LOC_MAIN_MK_FILE"
                        echo '$(warning LOCAL_PATH IS [$(LOCAL_PATH)].)' >> "$LOC_MAIN_MK_FILE"
                        echo -n '$(warning LOC_INS_DIR_TARGET IS [' >> "$LOC_MAIN_MK_FILE"
                        echo -n "${LOC_INS_DIR_TARGET}" >> "$LOC_MAIN_MK_FILE"
                        echo '].)' >> "$LOC_MAIN_MK_FILE"
                        echo -n '$(warning LOC_APK_NAME IS [' >> "$LOC_MAIN_MK_FILE"
                        echo -n "${LOC_APK_NAME}" >> "$LOC_MAIN_MK_FILE"
                        echo '].)' >> "$LOC_MAIN_MK_FILE"
                        echo -n '$(warning LOC_APK_FILE IS [' >> "$LOC_MAIN_MK_FILE"
                        echo -n "${LOC_APK_FILE}" >> "$LOC_MAIN_MK_FILE"
                        echo '].)' >> "$LOC_MAIN_MK_FILE"
                        echo -n '$(warning GEND_XML_OUTPUT IS [' >> "$LOC_MAIN_MK_FILE"
                        echo -n "${GEND_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                        echo '].)' >> "$LOC_MAIN_MK_FILE"
                        echo -n '$(warning TMP_XML_OUTPUT IS [' >> "$LOC_MAIN_MK_FILE"
                        echo -n "${TMP_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                        echo '].)' >> "$LOC_MAIN_MK_FILE"
                    fi
                    echo -n '$(shell PRODUCT_OUT=$(PRODUCT_OUT) HOST_OUT=$(HOST_OUT) ' >> "$LOC_MAIN_MK_FILE"
                    echo -n '$(LOCAL_PATH)/privapp_permissions.py ' >> "$LOC_MAIN_MK_FILE"
                    echo -n '--aapt=prebuilts/sdk/tools/linux/bin/aapt ' >> "$LOC_MAIN_MK_FILE"
                    echo -n '--output=' >> "$LOC_MAIN_MK_FILE"
                    echo -n '$(LOCAL_PATH)/' >> "$LOC_MAIN_MK_FILE"
                    echo -n "${TMP_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo -n ' $(LOCAL_PATH)/' >> "$LOC_MAIN_MK_FILE"
                    echo -n "${LOC_APK_FILE}" >> "$LOC_MAIN_MK_FILE"
                    echo ')' >> "$LOC_MAIN_MK_FILE"
                    echo '' >> "$LOC_MAIN_MK_FILE"

                    # Define and clear the MY_PRIV_APP_PERM_XML_CHECK flag. (In the make file.)
                    echo '# Documenation note, the reason for this variable is that' >> "$LOC_MAIN_MK_FILE"
                    echo '# GNU Make seems to only run the wildcard cmd once per given glob pattern.' >> "$LOC_MAIN_MK_FILE"
                    echo '# As a result, if we do not keep track of prior attempts we cannot make valid' >> "$LOC_MAIN_MK_FILE"
                    echo '# choices later on.' >> "$LOC_MAIN_MK_FILE"
                    echo '# I.e. When we have renamed / created a file that was absent during a previous' >> "$LOC_MAIN_MK_FILE"
                    echo '# call to wildcard. Subsequent wildcard calls will still act as if the file' >> "$LOC_MAIN_MK_FILE"
                    echo '# does not exist.' >> "$LOC_MAIN_MK_FILE"
                    echo 'MY_PRIV_APP_PERM_XML_CHECK := False' >> "$LOC_MAIN_MK_FILE"
                    echo '' >> "$LOC_MAIN_MK_FILE"

                    # Check if we have a new permissions file. (In the make file.)
                    echo -n 'ifneq (,$(wildcard $(LOCAL_PATH)/' >> "$LOC_MAIN_MK_FILE"
                    echo -n "${TMP_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo '))' >> "$LOC_MAIN_MK_FILE"

                    # Check if we need to append the generated XML file to a previous one. (In the make file.)
                    echo -n '    ifneq (,$(wildcard $(LOCAL_PATH)/' >> "$LOC_MAIN_MK_FILE"
                    echo -n "${GEND_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo '))' >> "$LOC_MAIN_MK_FILE"
                    # Remove the first two lines from the generated XML file. (In the make file.)
                    # Note: This removes the extra XML header lines which would otherwise cause 
                    # a parser error when the merged XML file was installed on the device.
                    echo -n '        $(shell sed -i -e ' >> "$LOC_MAIN_MK_FILE"
                    echo -ne "'1,2d' " >> "$LOC_MAIN_MK_FILE"
                    echo -n '$(LOCAL_PATH)/' >> "$LOC_MAIN_MK_FILE"
                    echo -n "${TMP_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo ')' >> "$LOC_MAIN_MK_FILE"
                    # Remove the last line from the original XML file. (In the make file.)
                    # Note: Again, this removes the extra XML footer line which would otherwise 
                    # cause a parser error when the merged XML file was installed on the device.
                    echo -n '        $(shell sed ' >> "$LOC_MAIN_MK_FILE"
                    echo -n "-i -n -e :a -e '1,1!{P;N;D;};N;ba' " >> "$LOC_MAIN_MK_FILE"
                    echo -n '$(LOCAL_PATH)/' >> "$LOC_MAIN_MK_FILE"
                    echo -n "${GEND_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo ')' >> "$LOC_MAIN_MK_FILE"
                    # Append the generated XML to the previous one. (In the make file.)
                    echo -n '        $(shell cat $(LOCAL_PATH)/' >> "$LOC_MAIN_MK_FILE"
                    echo -n "${TMP_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo -n ' >> $(LOCAL_PATH)/' >> "$LOC_MAIN_MK_FILE"
                    echo -n "${GEND_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo ')' >> "$LOC_MAIN_MK_FILE"
                    # Now remove the temp file. (In the make file.)
                    echo -n '        $(shell rm -f $(LOCAL_PATH)/' >> "$LOC_MAIN_MK_FILE"
                    echo -n "${TMP_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo ')' >> "$LOC_MAIN_MK_FILE"
                    # Otherwise, rename the generated XML to the correct name. (In the make file.)
                    echo '    else' >> "$LOC_MAIN_MK_FILE"
                    echo -n '        $(shell mv $(LOCAL_PATH)/' >> "$LOC_MAIN_MK_FILE"
                    echo -n "${TMP_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo -n ' $(LOCAL_PATH)/' >> "$LOC_MAIN_MK_FILE"
                    echo -n "${GEND_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo ')' >> "$LOC_MAIN_MK_FILE"
                    # Close the inner if statement (In the make file.)
                    echo '    endif' >> "$LOC_MAIN_MK_FILE"
                    # Set the MY_PRIV_APP_PERM_XML_CHECK flag. (In the make file.)
                    echo '    MY_PRIV_APP_PERM_XML_CHECK := True' >> "$LOC_MAIN_MK_FILE"
                    # Close the outer if statement (In the make file.)
                    echo 'endif' >> "$LOC_MAIN_MK_FILE"
                    echo '' >> "$LOC_MAIN_MK_FILE"

                    # Have the make file check for the final priv-app perms XML file.
                    # If it did not create a temp file. Have it set the MY_PRIV_APP_PERM_XML_CHECK
                    # flag if it finds it.
                    echo 'ifeq (False, $(MY_PRIV_APP_PERM_XML_CHECK))' >> "$LOC_MAIN_MK_FILE"
                    echo -n '    ifneq (,$(wildcard $(LOCAL_PATH)/' >> "$LOC_MAIN_MK_FILE"
                    echo -n "${GEND_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo '))' >> "$LOC_MAIN_MK_FILE"
                    echo '        MY_PRIV_APP_PERM_XML_CHECK := True' >> "$LOC_MAIN_MK_FILE"
                    echo '    endif' >> "$LOC_MAIN_MK_FILE"
                    echo 'endif' >> "$LOC_MAIN_MK_FILE"
                    echo '' >> "$LOC_MAIN_MK_FILE"

                    # Have the make file output the result of the XML file existance checks if script debugging is enabled.
                    if [ ${DEBUG_SCRIPT_ENABLED} -gt 0 ]; then
                        echo '$(warning MY_PRIV_APP_PERM_XML_CHECK is $(MY_PRIV_APP_PERM_XML_CHECK).)' >> "$LOC_MAIN_MK_FILE"
                        echo '' >> "$LOC_MAIN_MK_FILE"
                    fi

                    # Have the make file check and see if it should define the priv-app perms XML module.
                    echo 'ifeq (True, $(MY_PRIV_APP_PERM_XML_CHECK))' >> "$LOC_MAIN_MK_FILE"

                    # Have the make file inform that it is generating the priv-app perms xml file module definition
                    # if script debugging is enabled.
                    if [ $DEBUG_SCRIPT_ENABLED -gt 0 ]; then
                        echo '    $(warning XML PERMS FILE FOUND. Generating Local module definition.)' >> "$LOC_MAIN_MK_FILE"
                    fi

                    # Include the priv-app permissions.xml module in the output.
                    echo -n '    MY_PRIV_APP_PERM_XML_MODULE := ' >> "$LOC_MAIN_MK_FILE"
                    echo "${PRIV_APP_XML_MOD_NAME}" >> "$LOC_MAIN_MK_FILE"
                    # Output the make file command to copy the resulting XML file to the proper directory.
                    echo '    include $(CLEAR_VARS)' >> "$LOC_MAIN_MK_FILE"
                    echo -n '    LOCAL_MODULE := ' >> "$LOC_MAIN_MK_FILE"
                    echo "${PRIV_APP_XML_MOD_NAME}" >> "$LOC_MAIN_MK_FILE"
                    echo -n '    LOCAL_SRC_FILES := ' >> "$LOC_MAIN_MK_FILE"
                    echo "${GEND_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo '    LOCAL_MODULE_CLASS := ETC' >> "$LOC_MAIN_MK_FILE"
                    echo '    LOCAL_MODULE_TAGS := optional' >> "$LOC_MAIN_MK_FILE"
                    echo -n '    LOCAL_MODULE_PATH := ' >> "$LOC_MAIN_MK_FILE"
                    echo '$(TARGET_OUT_ETC)/permissions' >> "$LOC_MAIN_MK_FILE"
                    echo -n '    LOCAL_MODULE_STEM := ' >> "$LOC_MAIN_MK_FILE"
                    echo "${GEND_XML_OUTPUT}" >> "$LOC_MAIN_MK_FILE"
                    echo '    include $(BUILD_PREBUILT)' >> "$LOC_MAIN_MK_FILE"

                    # Close the outer if statement (In the make file.)
                    echo 'endif' >> "$LOC_MAIN_MK_FILE"
                    echo '' >> "$LOC_MAIN_MK_FILE"

                    # Clean up vars.
                    unset GEND_XML_OUTPUT
                    unset TMP_XML_OUTPUT
                    unset PRIV_APP_XML_MOD_NAME
                fi

                # Begin main APK module definition.
                echo 'include $(CLEAR_VARS)' >> "$LOC_MAIN_MK_FILE"
                echo -n 'LOCAL_MODULE := ' >> "$LOC_MAIN_MK_FILE"
                echo "$LOC_APK_NAME" >> "$LOC_MAIN_MK_FILE"
                echo -n 'LOCAL_SRC_FILES := ' >> "$LOC_MAIN_MK_FILE"
                echo "$LOC_APK_FILE" >> "$LOC_MAIN_MK_FILE"
                echo 'LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)' >> "$LOC_MAIN_MK_FILE"
                echo 'LOCAL_MODULE_CLASS := APPS' >> "$LOC_MAIN_MK_FILE"
                echo 'LOCAL_MODULE_TAGS := optional' >> "$LOC_MAIN_MK_FILE"
                echo -n 'LOCAL_MODULE_PATH := ' >> "$LOC_MAIN_MK_FILE"
                # Note: We can't use LOC_INS_DIR_TARGET here as is due to the AOSP build
                # system appending the module name to the LOCAL_MODULE_PATH option internally.
                if [ "$2" == "priv-app" ]; then
                    # Privileged app....
                    echo "\$(TARGET_OUT_APPS_PRIVILEGED)" >> "$LOC_MAIN_MK_FILE"
                else
                    # Normal app....
                    echo "\$(TARGET_OUT_APPS)" >> "$LOC_MAIN_MK_FILE"
                fi
                echo 'LOCAL_CERTIFICATE := PRESIGNED' >> "$LOC_MAIN_MK_FILE"
                if [ "$2" == "priv-app" ]; then
                    # Privileged app....
                    echo 'LOCAL_PRIVILEGED_MODULE := true' >> "$LOC_MAIN_MK_FILE"
                else
                    # Normal app....
                    echo 'LOCAL_PRIVILEGED_MODULE := false' >> "$LOC_MAIN_MK_FILE"
                fi

                # Check if we need to create a LOCAL_REQUIRED_MODULES section.
                if [ $LOC_LIB_NAMES_LEN -gt 0 -a "$LOC_LIB_NAMES" != "" ]; then
                    echo -n 'LOCAL_REQUIRED_MODULES := ' >> "$LOC_MAIN_MK_FILE"           
                    echo "${LOC_LIB_NAMES[@]}" >> "$LOC_MAIN_MK_FILE"
                fi

                # Include the priv_app permissions.xml file module if needed.
                if [ "$2" == "priv-app" ]; then
                    # Have the make file check for the module's presence.
                    echo 'ifneq ($(strip $(MY_PRIV_APP_PERM_XML_MODULE)),)' >> "$LOC_MAIN_MK_FILE"
                    echo '    LOCAL_REQUIRED_MODULES += $(MY_PRIV_APP_PERM_XML_MODULE)' >> "$LOC_MAIN_MK_FILE"
                    # If script debugging is enabled, have the make file inform that it has included the
                    # priv-app permissions XML file.
                    if [ $DEBUG_SCRIPT_ENABLED -gt 0 ]; then
                        echo '    $(warning INCLUDED PRIV-APP PERMISSIONS XML MODULE.)' >> "$LOC_MAIN_MK_FILE"
                    fi
                    echo 'endif' >> "$LOC_MAIN_MK_FILE"
                fi

                # Output the final commands for the main Android.mk file.
                echo 'include $(BUILD_PREBUILT)' >> "$LOC_MAIN_MK_FILE"
                echo '' >> "$LOC_MAIN_MK_FILE"
                echo '# These are blanked as undefine does not seem to work here.' >> "$LOC_MAIN_MK_FILE"
                echo 'MY_PRIV_APP_PERM_XML_CHECK := ' >> "$LOC_MAIN_MK_FILE"
                echo 'MY_PRIV_APP_PERM_XML_MODULE := ' >> "$LOC_MAIN_MK_FILE"
                echo 'MY_APP_LOCAL_PATH := ' >> "$LOC_MAIN_MK_FILE"
                echo '' >> "$LOC_MAIN_MK_FILE"

                # Output the PRODUCT_PACKAGE update to a text file.
                echo '# NOTE: The contents below must be added to one of the makefiles for your device.' > 'ADD_TO_DEVICE_MAKE_FILE.txt'
                echo '# The setup.bash script cannot do this for you as it does not know what file needs to be patched.' >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                echo '# As the file to patch is device specific, and build system specific.' >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                echo '# You can thank Google for making your life difficult. As Google removed the "LOCAL_MODULE_TAGS := user" option which used to do this automatically.' >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                echo '# Why? Because stripped down builds. Nope not kidding. Apparently its too difficult for Google to add a "LOCAL_MODULE_BUILD_LEVEL := platformreq | core | userexperience | optional" config option....' >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                echo '' >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                echo '# WARNING: The spacing must be kept exactly as shown or soong will throw a fit during the build.' >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                echo '# For those that need help: The format is one tab, the module name, an optional space and \ character if another module is to follow, and a newline character.' >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                echo '# E.x. [<TAB>libfoo.so<SPACE>\<NEWLINE>] or [<TAB>libfoo.so<NEWLINE>]' >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                echo 'PRODUCT_PACKAGES += \' >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                if [ $LOC_SONAME_ARR_IDX -gt 0 ]; then
                    # NOTE: The spacing here is important. soong has a fit if the file has a space or tab out of place....
                    echo -e "\t$LOC_APK_NAME \\" >> 'ADD_TO_DEVICE_MAKE_FILE.txt'

                    declare -i COUNT_IDX
                    declare -i NEXT_IDX
                    COUNT_IDX=0
                    declare -i LOC_SONAME_ARR_LEN
                    LOC_SONAME_ARR_LEN=${#LOC_SONAME_ARR[@]}
                    for i in "${LOC_SONAME_ARR[@]}"; do
                        NEXT_IDX=$COUNT_IDX+1
                        if [ $NEXT_IDX -ge $LOC_SONAME_ARR_LEN ]; then
                            echo -e "\t${i}" >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                        else
                            echo -e "\t${i} \\" >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                            COUNT_IDX=$COUNT_IDX+1
                        fi
                    done

                    unset COUNT_IDX
                    unset NEXT_IDX
                    unset LOC_SONAME_ARR_LEN
                else
                    echo -e "\t$LOC_APK_NAME" >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                fi
                echo "" >> 'ADD_TO_DEVICE_MAKE_FILE.txt'
                sync

                # If the user specified it, attempt to patch the device make file....
                if [ "$DEVICE_MAKEFILE" != "" ]; then
                    cat 'ADD_TO_DEVICE_MAKE_FILE.txt' >> "${DEVICE_MAKEFILE}"
                    sync
                fi
            else
                # Destroy generated Android.mk files...
                rm -f "$LOC_MAIN_MK_FILE"
                rm -rf "$EXTRACTED_LIB_FOLDER"

                # Exit function.
                return -1
            fi
        else
            echo "ERROR: No APK package name given. Got: ( $3 )" >&2
            return -1
        fi
    else
        echo "ERROR: No APK name given. Aborting." >&2
        return -1
    fi
else
    echo "ERROR: Invalid arguments." >&2
    return -1
fi

# Done.
return 0
}

# Declare vars.
OUT_DIR=""
DEVICE_MAKEFILE=""
if [ "$DEBUG_SCRIPT_ENABLED" == "" ]; then
    DEBUG_SCRIPT_ENABLED=0
fi

# Determine if an output directory was defined on the command line.
if [ "$#" -gt 0 -a "$1" != "" ]; then
    if [ -d "$1" -o -L "$1" ]; then
        OUT_DIR="$1"
    else
        echo "ERROR: Invalid output directory defined on command line. Aborting."
    fi
else
    # Check if an "output directory" exists in the current directory.
    if [ -d "${PWD}/output" -o -L "${PWD}/output" ]; then
        OUT_DIR="${PWD}/output"
    else
        echo "ERROR: Output directory not defined on command line or present in current path."
        echo "ERROR: Either create an output directory at ( ${PWD}/output )  - OR -" 
        echo "ERROR: define the output directory as the first argument to this script."
        echo "ERROR: You probably want to use the <AOSP TOP LEVEL SOURCE DIRECTORY>/packages/apps directory here."
    fi
fi

# Output the patch for loading the additional priv-apps permissions file(s).
TOP_DEV_MK_PATCH="ADD_TO_DEVICE_MAKEFILE_TOP.txt"
if [ -f "$TOP_DEV_MK_PATCH" ]; then
    rm -f "$TOP_DEV_MK_PATCH"
fi
echo '# --- Begin setup.bash autogenerated commands --- ' > "$TOP_DEV_MK_PATCH"
echo '# Note: If you wish to update this file, restore the {FILENAME}.before_setup.bash.txt file first and edit it.' >> "$TOP_DEV_MK_PATCH"
echo '# Otherwise your changes *WILL* be lost on the next run of the setup.bash script!!!!!' >> "$TOP_DEV_MK_PATCH"
echo '' >> "$TOP_DEV_MK_PATCH"
echo '# Patch for including priv-app permissions whitelist files from ( ${PWD}/local_permissions ).' >> "$TOP_DEV_MK_PATCH"
echo 'ifneq (,$(wildcard $(LOCAL_PATH)/local_permissions/*.xml))' >> "$TOP_DEV_MK_PATCH"
echo -n -e "\t" >> "$TOP_DEV_MK_PATCH"
echo 'PRODUCT_COPY_FILES += $(foreach file,$(wildcard $(LOCAL_PATH)/local_permissions/*.xml),$(file):system/etc/permissions/$(notdir $(file)) )' >> "$TOP_DEV_MK_PATCH"
echo 'endif' >> "$TOP_DEV_MK_PATCH"
echo '' >> "$TOP_DEV_MK_PATCH"

# Check for output path.
if [ "$OUT_DIR" != "" ]; then
    if [ "$#" -gt 1 -a "$2" != "" ]; then
        if [ -f "$2" ]; then
            echo "WARNING: You've requested to patch the device make file. This is NOT recommended, as it may destroy the device make file. USE AT YOUR OWN RISK."
            DEVICE_MAKEFILE="$2"
            # Create backup if needed.
            if [ ! -f "${DEVICE_MAKEFILE}.before_setup.bash.txt" ]; then
                echo "WARNING: Creating initial backup of device make file ( ${DEVICE_MAKEFILE}.before_setup.bash.txt ). This is only done once to avoid corruption on subsequent runs."
                echo "WARNING: If you make any external / manual changes to the device make file after this initial backup, they WILL be lost on subsequent runs of this script!"
                echo "WARNING: If you want to make a new initial backup, delete the ( ${DEVICE_MAKEFILE}.before_setup.bash.txt ) manually."
                cp -f "$DEVICE_MAKEFILE" "${DEVICE_MAKEFILE}.before_setup.bash.txt"
                retC=$?
                sync
                if [ $retC -eq 0 -a -f "${DEVICE_MAKEFILE}.before_setup.bash.txt" ]; then
                    echo "INFO: Initial backup of device make file ( ${DEVICE_MAKEFILE}.before_setup.bash.txt ) created successfully."
                else
                    echo "ERROR: Failed to create initial backup of the device make file. Script will now abort to avoid corrupting the device make file."
                    exit -1
                fi
            else
                echo "WARNING: Restoring initial backup of device make file ( ${DEVICE_MAKEFILE}.before_setup.bash.txt ). This is done to avoid duplicate entries in the device make file."
                echo "WARNING: If you have made any external / manual changes to the device make file since the initial backup, they are now gone. Hope they were not important."
                echo "WARNING: If you want to make a new initial backup, delete the ( ${DEVICE_MAKEFILE}.before_setup.bash.txt ) manually."
                cp -f "${DEVICE_MAKEFILE}.before_setup.bash.txt" "$DEVICE_MAKEFILE"
                retC=$?
                sync
                if [ $retC -eq 0 ]; then
                    echo "INFO: Restored initial backup of device make file successfully."
                else
                    echo "ERROR: Unable to restore initial backup of the device make file. Script will now abort to avoid corrupting the device make file."
                    exit -1
                fi
            fi

            # Patch the device makefile with the initial autogenerated priv-apps permissions whitelist patch.
            cat "${TOP_DEV_MK_PATCH}" >> "${DEVICE_MAKEFILE}"
        fi
    else
        echo "INFO: No device make file specified."
        echo "INFO: You NEED to patch the device makefile with the contents of ( ${OUT_DIR}/APK NAME/ADD_TO_DEVICE_MAKE_FILE.txt ) for each APK."
        echo "INFO: Otherwise, the APKs and their shared libraries will NOT be installed on the generated system image!!!!"
        echo "INFO: You also need to patch the device makefile with the contents of ( ${PWD}/${TOP_DEV_MK_PATCH} ) so that priv-apps that need additional permissions will get them."
        echo "INFO: Otherwise, your device WILL NOT BOOT if you flash the resulting system.img!!!! (This is a requirement of Android 9 and later.)"
    fi

    # Check for needed scripts.
    TOP_PATH=${PWD}
    if [ -f "${PWD}/create_native_lib_mk_files.bash" ]; then
        NATIVE_LIB_SCRIPT="${PWD}/create_native_lib_mk_files.bash"
        # Check for apks.
        if [ -d "${PWD}/source_apks" -a -d "${PWD}/source_apks/app" -a -d "${PWD}/source_apks/priv-app" ]; then
            # Process 'normal' APPs.
            echo "INFO: Processing 'normal' apps...."
            pushd "source_apks/app" &> /dev/null
            retC=$?
            if [ $retC -eq 0 ]; then
                for i in *.apk; do
                    # Skip the wildcard.
                    if [ "$i" == "*.apk" ]; then
                        continue
                    else
                        # Create output directory for the current apk.
                        LOC_APK_FILE="$i"
                        STR_LEN="${#i}"
                        LOC_APK_NAME="${LOC_APK_FILE:0:$STR_LEN-4}" # Remove ".apk" file extension.
                        if [ -d "${OUT_DIR}/${LOC_APK_NAME}" ]; then
                            rm -rf "${OUT_DIR}/${LOC_APK_NAME}/*"
                        else
                            mkdir "${OUT_DIR}/${LOC_APK_NAME}"
                            retC=$?
                            if [ $retC -ne 0 ]; then
                                echo "ERROR: Unable to create output directory ( ${OUT_DIR}/${LOC_APK_NAME} ) for APK ( ${i} ). Skipping."
                                break
                            fi
                        fi
                        # Copy the current apk.
                        cp -f "$i" "${OUT_DIR}/${LOC_APK_NAME}/$i"
                        retC=$?
                        if [ $retC -eq 0 ]; then
                            # Copy the custom privapp_permissions.py file.
                            cp -f "${TOP_PATH}/privapp_permissions.py" "${OUT_DIR}/${LOC_APK_NAME}/privapp_permissions.py"
                            retC=$?
                            if [ $retC -eq 0 ]; then
                                pushd "${OUT_DIR}/${LOC_APK_NAME}" &> /dev/null
                                retC=$?
                                if [ $retC -eq 0 ]; then
                                    process_apk "$i" "app" "${LOC_APK_NAME}"
                                    popd &> /dev/null
                                else
                                    echo "WARNING: Could not enter output directory ( ${OUT_DIR}/${LOC_APK_NAME} ). Aborting."
                                    exit -1
                                fi
                            else
                                echo "WARNING: Could not copy privapp_permissions.py for APK ( $i ) to output directory. Skipping APK."
                            fi
                        else
                            echo "WARNING: Could not copy APK ( $i ) to output directory. Skipping APK."
                        fi
                    fi
                done
                popd &> /dev/null
            else
                echo "WARNING: Unable to enter directory ( ${PWD}/source_apks/app ) Skipping normal app processing."
            fi

            echo "INFO: Processing 'privileged' apps...."
            pushd "source_apks/priv-app" &> /dev/null
            retC=$?
            if [ $retC -eq 0 ]; then
                # Process 'privileged' APPs.
                for i in *.apk; do
                    # Skip the wildcard.
                    if [ "$i" == "*.apk" ]; then
                        continue
                    else
                        # Create output directory for the current apk.
                        LOC_APK_FILE="$i"
                        STR_LEN="${#i}"
                        LOC_APK_NAME="${LOC_APK_FILE:0:$STR_LEN-4}" # Remove ".apk" file extension.
                        if [ -d "${OUT_DIR}/${LOC_APK_NAME}" ]; then
                            rm -rf "${OUT_DIR}/${LOC_APK_NAME}/*"
                        else
                            mkdir "${OUT_DIR}/${LOC_APK_NAME}"
                            retC=$?
                            if [ $retC -ne 0 ]; then
                                echo "ERROR: Unable to create output directory ( ${OUT_DIR}/${LOC_APK_NAME} ) for APK ( ${i} ). Skipping."
                                break
                            fi
                        fi
                        # Copy the current apk.
                        cp -f "$i" "${OUT_DIR}/${LOC_APK_NAME}/$i"
                        retC=$?
                        if [ $retC -eq 0 ]; then
                            # Copy the custom privapp_permissions.py file.
                            cp -f "${TOP_PATH}/privapp_permissions.py" "${OUT_DIR}/${LOC_APK_NAME}/privapp_permissions.py"
                            retC=$?
                            if [ $retC -eq 0 ]; then
                                pushd "${OUT_DIR}/${LOC_APK_NAME}" &> /dev/null
                                retC=$?
                                if [ $retC -eq 0 ]; then
                                    process_apk "$i" "priv-app" "${LOC_APK_NAME}"
                                    popd &> /dev/null
                                else
                                    echo "WARNING: Could not enter output directory ( ${OUT_DIR}/${LOC_APK_NAME} ). Aborting."
                                    exit -1
                                fi
                            else
                                echo "WARNING: Could not copy privapp_permissions.py for APK ( $i ) to output directory. Skipping APK."
                            fi
                        else
                            echo "WARNING: Could not copy APK ( $i ) to output directory. Skipping APK."
                        fi
                    fi
                done
                popd &> /dev/null
            else
                echo "WARNING: Unable to enter directory ( ${PWD}/source_apks/priv-app ) Skipping privileged app processing."
            fi
            
            echo "Done."
        else
            echo "ERROR: Missing needed source_apks/app and source_apks/priv-app subdirectories. Aborting."
        fi
    else
        echo "ERROR: Missing create_native_lib_mk_files.bash script. Aborting."
    fi
fi

