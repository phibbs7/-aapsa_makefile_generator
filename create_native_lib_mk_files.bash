#!/bin/bash

# This script is a generic script for generating Android.mk make file(s) for an apk's shared libraries
# so that the apk may be installed into the system partition as a prebuilt app.

# This script also creates a "build-$2-libnames.txt" file which contains a list of all of the SONAMES for
# the libraries that had Android.mk files generated. Where $2 is the APK's package name as described below.
# In the case of multiarch APKs, only the first occurance of an SONAME is placed in the list so that the list
# will not contain duplicates.

# The first argument to the script is the APK installation directory on the target.
# E.x. "/system/app/com.example.some.package.name"

# The second argument to the script is the APK's package name. (Without the APK file extension.)
# E.x. "com.example.some.package.name"

# The return value of this script is the number of shared libraries that we made Android.mk files for.
# (Including duplicates caused by multiarch APKs.)



# Define ARM Variant lists.
# Note: These should be all lowercase and 
# listed in lowest ABI level (Most compatibility) to highest ABI level (least compatibility) order.
# ARM32 Variants.
ARM_32_VARIANTS[0]="armeabi"
ARM_32_VARIANTS[1]="armeabi-v7a"

# ARM64 Variants.
ARM_64_VARIANTS[0]="arm64-v8a"

retC=0
if [ $# -eq 2 ]; then
    if [ "$1" != "" -a "$2" != "" ]; then
        LOC_TARGET_INSTALL_PATH="$1"
        BUILD_MKFILE_TMP="${PWD}/build"

        for i in *.mk;
        do
            if [ "$i" == "*.mk" ]; then
                continue
            fi
            rm -f "$i"
        done

        if [ -f "$BUILD_MKFILE_TMP-$2-libnames.txt" ]; then
            rm -f "$BUILD_MKFILE_TMP-$2-libnames.txt"
        fi

        TMP_ARR_IDX=0
        declare -a LIB_ARR
        
        if [ -d "lib" ]; then
            pushd "lib" &> /dev/null
            retPush=$?
            if [ $retPush -eq 0 ]; then
                # Note: We have to clean up the arch names here.
                # The AOSP build system is *very* sensitive about arch names and, of course,
                # the ABI names are not mapped to the arch names.
                # I.e. If TARGET_ARCH=arm64 then 
                # LOCAL_MODULE_TARGET_ARCH := arm64-v8a will *NOT* match the target, and
                # the build system will exclude the module from the built system image.
                # Currently I do not know of any ABI matching rule to use here.

                # Define the currently selected ARM variants.
                CURRENT_ARM32_VAR=""
                CURRENT_ARM64_VAR=""

                # Declare remaining vars.
                declare -a ARCH_VARIANTS
                declare -i ARCH_VARIANTS_IDX                
                ARCH_VARIANTS_IDX=0
                for d in *;
                do
                    # Skip bad directory.
                    if [ ! -d "${d}" ]; then
                        continue
                    else
                        # Generate lower case version of the directory name.
                        TMP_STR="`echo "${d}" | tr '[:upper:]' '[:lower:]'`"

                        # Check and see if we are dealing with an ARM variant.
                        if [ ${#TMP_STR} -ge 3 -a "arm" == "${TMP_STR:0:3}" ]; then
                            # ARM variant. Determine bitness.
                            if [ ${#TMP_STR} -ge 5 -a "arm64" == "${TMP_STR:0:5}" ]; then
                                # ARM64 bit.
                                # Determine lowest common variant.
                                if [ "${CURRENT_ARM64_VAR}" == "" ]; then
                                    # No current variant selected. Use this one for now.
                                    CURRENT_ARM64_VAR="${d}"
                                else
                                    # Determine if the directory's variant is even in the list of known variants.
                                    declare -i COUNT_IDX
                                    COUNT_IDX=0

                                    while [ $COUNT_IDX -lt ${#ARM_64_VARIANTS[@]} ];
                                    do
                                        # Check and see if the current variant is a match.
                                        if [ "${ARM_64_VARIANTS[$COUNT_IDX]}" == "${TMP_STR}" ]; then
                                            # Current variant is a match.
                                            break
                                        else
                                            # Increment COUNT_IDX.
                                            COUNT_IDX=$COUNT_IDX+1
                                        fi
                                    done
                                    if [ $COUNT_IDX -le ${#ARM_64_VARIANTS[@]} ]; then
                                        # Directory's variant is known. See if the currently selected variant is lower than the directory's variant on the list.
                                        declare -i DIR_VARIANT
                                        DIR_VARIANT=$COUNT_IDX
                                        COUNT_IDX=0

                                        CUR_STR="`echo "${CURRENT_ARM64_VAR}" | tr '[:upper:]' '[:lower:]'`"
                                        while [ $COUNT_IDX -lt ${#ARM_64_VARIANTS[@]} ];
                                        do
                                            # Check and see if the current variant is a match.
                                            if [ "${ARM_64_VARIANTS[$COUNT_IDX]}" == "${CUR_STR}" ]; then
                                                # Current variant is a match.
                                                break
                                            else
                                                # Increment COUNT_IDX.
                                                COUNT_IDX=$COUNT_IDX+1
                                            fi
                                        done
                                        # Clean up CUR_STR.
                                        unset CUR_STR
                                        if [ $COUNT_IDX -le ${#ARM_64_VARIANTS[@]} ]; then
                                            # Both current and directory are known variants. Determine which one has a lower ABI level and choose it.
                                            if [ $DIR_VARIANT -le $COUNT_IDX ]; then
                                                # Directory variant has the lower ABI level. Selecting it as the current ABI to use.
                                                CURRENT_ARM64_VAR="${d}"
                                            fi
                                        else
                                            # An UNKNOWN variant was found previously. (Was probably the first one we found.)
                                            # Warn the user and choose the known variant instead.
                                            echo "WARNING: Encountered unknown ARM ABI variant ( ${CURRENT_ARM64_VAR} ) for APK ( ${2} ). You should update create_native_lib_mk_files.bash to be aware of the new variant." >&2
                                            echo "WARNING: Otherwise, if a known ARM ABI variant is found it will be prioritised over this unknown variant by default." >&2                               
                                            CURRENT_ARM64_VAR="${d}"
                                        fi
                                        
                                        # Clean up DIR_VARIANT and CUR_STR.
                                        unset DIR_VARIANT
                                        unset CUR_STR
                                    else
                                        # UNKNOWN variant. Warn the user and ignore it.
                                        echo "WARNING: Encountered unknown ARM ABI variant ( ${TMP_STR} ) for APK ( ${2} ). You should update create_native_lib_mk_files.bash to be aware of the new variant." >&2
                                        echo "WARNING: Otherwise, if a known ARM ABI variant is found it will be prioritised over this unknown variant by default." >&2
                                    fi
                                    
                                    # Clean up COUNT_IDX.
                                    unset COUNT_IDX
                                fi
                            else
                                # ARM32 bit.
                                # Determine lowest common variant.
                                if [ "${CURRENT_ARM32_VAR}" == "" ]; then
                                    # No current variant selected. Use this one for now.
                                    CURRENT_ARM32_VAR="${d}"
                                else
                                    # Determine if the directory's variant is even in the list of known variants.
                                    declare -i COUNT_IDX
                                    COUNT_IDX=0

                                    while [ $COUNT_IDX -lt ${#ARM_32_VARIANTS[@]} ];
                                    do
                                        # Check and see if the current variant is a match.
                                        if [ "${ARM_32_VARIANTS[$COUNT_IDX]}" == "${TMP_STR}" ]; then
                                            # Current variant is a match.
                                            break
                                        else
                                            # Increment COUNT_IDX.
                                            COUNT_IDX=$COUNT_IDX+1
                                        fi
                                    done
                                    if [ $COUNT_IDX -le ${#ARM_32_VARIANTS[@]} ]; then
                                        # Directory's variant is known. See if the currently selected variant is lower than the directory's variant on the list.
                                        declare -i DIR_VARIANT
                                        DIR_VARIANT=$COUNT_IDX
                                        COUNT_IDX=0

                                        CUR_STR="`echo "${CURRENT_ARM32_VAR}" | tr '[:upper:]' '[:lower:]'`"
                                        while [ $COUNT_IDX -lt ${#ARM_32_VARIANTS[@]} ];
                                        do
                                            # Check and see if the current variant is a match.
                                            if [ "${ARM_32_VARIANTS[$COUNT_IDX]}" == "${CUR_STR}" ]; then
                                                # Current variant is a match.
                                                break
                                            else
                                                # Increment COUNT_IDX.
                                                COUNT_IDX=$COUNT_IDX+1
                                            fi
                                        done
                                        # Clean up CUR_STR.
                                        unset CUR_STR
                                        if [ $COUNT_IDX -le ${#ARM_32_VARIANTS[@]} ]; then
                                            # Both current and directory are known variants. Determine which one has a lower ABI level and choose it.
                                            if [ $DIR_VARIANT -le $COUNT_IDX ]; then
                                                # Directory variant has the lower ABI level. Selecting it as the current ABI to use.
                                                CURRENT_ARM32_VAR="${d}"
                                            fi
                                        else
                                            # An UNKNOWN variant was found previously. (Was probably the first one we found.)
                                            # Warn the user and choose the known variant instead.
                                            echo "WARNING: Encountered unknown ARM ABI variant ( ${CURRENT_ARM32_VAR} ) for APK ( ${2} ). You should update create_native_lib_mk_files.bash to be aware of the new variant." >&2
                                            echo "WARNING: Otherwise, if a known ARM ABI variant is found it will be prioritised over this unknown variant by default." >&2                               
                                            CURRENT_ARM32_VAR="${d}"
                                        fi

                                        # Clean up DIR_VARIANT and CUR_STR.
                                        unset DIR_VARIANT
                                        unset CUR_STR
                                    else
                                        # UNKNOWN variant. Warn the user and ignore it.
                                        echo "WARNING: Encountered unknown ARM ABI variant ( ${TMP_STR} ) for APK ( ${2} ). You should update create_native_lib_mk_files.bash to be aware of the new variant." >&2
                                        echo "WARNING: Otherwise, if a known ARM ABI variant is found it will be prioritised over this unknown variant by default." >&2
                                    fi

                                    # Clean up COUNT_IDX.
                                    unset COUNT_IDX
                                fi
                            fi
                        else
                            # Not an ARM variant, add to the valid arch variants list.
                            ARCH_VARIANTS[$ARCH_VARIANTS_IDX]="${d}"
                            ARCH_VARIANTS_IDX=$ARCH_VARIANTS_IDX+1
                        fi
                    fi
                done

                # Add selected ARM variants if needed.
                if [ "${CURRENT_ARM32_VAR}" != "" ]; then
                    ARCH_VARIANTS[$ARCH_VARIANTS_IDX]="${CURRENT_ARM32_VAR}"
                    ARCH_VARIANTS_IDX=$ARCH_VARIANTS_IDX+1
                fi
                if [ "${CURRENT_ARM64_VAR}" != "" ]; then
                    ARCH_VARIANTS[$ARCH_VARIANTS_IDX]="${CURRENT_ARM64_VAR}"
                    ARCH_VARIANTS_IDX=$ARCH_VARIANTS_IDX+1
                fi

                # Generate the Android.mk files for the valid variants.
                for d in "${ARCH_VARIANTS[@]}";
                do
                    if [ -d "$d" ]; then
                        pushd "$d" &> /dev/null
                        retPush=$?
                        if [ $retPush -eq 0 ]; then
                            for i in *;
                            do
                                # Skip wildcard.
                                if [ "$i" == "*" ]; then
                                    continue
                                else
                                    # Check array to see if the SONAME is already present.
                                    TMP_LEN="${#i}"
                                    TMP_NAME="${i:0:$TMP_LEN-3}"
                                    TMP_ADD=1
                                    for z in "${LIB_ARR[@]}"; do
                                        if [ "$z" == "$TMP_NAME" ]; then
                                            # Found the library name. Do not add it to the list.
                                            TMP_ADD=0
                                            break
                                        fi
                                    done

                                    # Add the SONAME if needed.
                                    if [ $TMP_ADD -eq 1 ]; then
                                        LIB_ARR[$TMP_ARR_IDX]="$TMP_NAME"
                                        TMP_ARR_IDX=$TMP_ARR_IDX+1
                                    fi

                                    BUILD_MKFILE="${BUILD_MKFILE_TMP}-${2}-${d}-${i}.mk"
                                    echo 'include $(CLEAR_VARS)' >> "$BUILD_MKFILE"
                                    echo -n 'LOCAL_MODULE := ' >> "$BUILD_MKFILE"
                                    echo "${2}-${TMP_NAME}" >> "$BUILD_MKFILE"
                                    echo -n 'LOCAL_SRC_FILES := ' >> "$BUILD_MKFILE"
                                    echo "lib/${d}/${i}" >> "$BUILD_MKFILE"
                                    echo 'LOCAL_MODULE_TAGS := optional' >> "$BUILD_MKFILE"
                                    echo 'LOCAL_MODULE_CLASS := SHARED_LIBRARIES' >> "$BUILD_MKFILE"
                                    echo -n 'LOCAL_MODULE_PATH := ' >> "$BUILD_MKFILE"
                                    echo "${LOC_TARGET_INSTALL_PATH}/lib/${d}" >> "$BUILD_MKFILE"
                                    echo -n 'LOCAL_MODULE_STEM := ' >> "$BUILD_MKFILE"
                                    echo "${i}" >> "$BUILD_MKFILE"

                                    # Output arch type.
                                    echo -n 'LOCAL_MODULE_TARGET_ARCH := ' >> "$BUILD_MKFILE"

                                    # Check and see if the current arch is a selected ARM arch.
                                    if [ "${d}" == "${CURRENT_ARM32_VAR}" ]; then
                                        # ARM 32 arch. (Should output "arm" here...)
                                        echo "arm" >> "$BUILD_MKFILE"
                                    else
                                        if [ "${d}" == "${CURRENT_ARM64_VAR}" ]; then
                                            # ARM 64 arch. (Should output "arm64" here...)
                                            echo "arm64" >> "$BUILD_MKFILE"
                                        else
                                            # Not a selected ARM arch, just output the name.
                                            echo "${d}" >> "$BUILD_MKFILE"
                                        fi
                                    fi

                                    echo 'include $(BUILD_PREBUILT)' >> "$BUILD_MKFILE"
                                    sync

                                    # Clean up.
                                    unset TMP_LEN
                                    unset TMP_NAME
                                fi
                            done
                            retC=${retC+1}
                            popd &> /dev/null
                        else
                            echo "ERROR: Unable to enter directory ( $PWD/lib/$d )." >&2
                            retC=0
                            unset LIB_ARR
                            declare -a LIB_ARR
                            break
                        fi
                    fi
                done
                # Exit the lib directory.
                popd &> /dev/null
                
                # Create the SONAME list file.
                if [ $retC -gt 0 ]; then
                    for z in "${LIB_ARR[@]}"; do
                        echo -n "${2}-${z} " >> "$BUILD_MKFILE_TMP-$2-libnames.txt"
                    done
                    unset LIB_ARR
                fi
            else
                echo "ERROR: Unable to enter directory ( $PWD/lib )." >&2
            fi
        fi
    fi
fi

# Return the number of libs that we made mk files for.
exit $retC

