#!/bin/bash -e
set +x

MY_PATH=$(dirname $(realpath "$0"))
cd $MY_PATH

BRANCH_COMMITS="reference"
BRANCH_MAIN="a12/master"
BUILD_FLAGS="-j$(nproc) LLVM=1"
COMMITMSG_LEGACY_OMX="This reverts commit e265d46203a6a01abb9824933dee5641f4aff428"
COMMITMSG_OLD_VIB_DTS="ARM64: dts: Bring back old vibrator nodes"
SUPPORTED_ANDROID_VERSIONS="8.1.0 - 12"

if ! git --version > /dev/null; then
    echo "Git does not work."
    exit 1
fi
if ! [ -d ".git" ] || ! [ -d ".ak3" ];then
    echo "The tree is broken."
    exit 1
fi

func_help() {
    echo "Build script of Mi8937 All-In-One Kernel"
    echo
    echo "Parameters or Environment variables:"
    echo " Required:"
    echo "  --llvm-path | LLVM_PATH"
    echo "  --out | OUT"
    echo
    echo " Optional:"
    echo "  --artifact-copy | ARTIFACT_COPY"
    echo "  --artifact-upload | ARTIFACT_UPLOAD"
    echo "  --branch | BRANCH"
    echo "  --cherry-pick | CHERRY_PICK"
    echo "  --legacy-omx | LEGACY_OMX"
    echo "  --lto | LTO"
    echo "  --partition | PARTITION"
}

func_get_commitid_by_msg() {
    git log --grep="$1" $BRANCH_COMMITS 2>/dev/null|head -n 1|cut -c 8-
}

func_set_defconfig() {
    cfg="$1"
    item="$2"
    value="$3"
    sed -i "/${item}=/d" $cfg
    echo "${item}=${value}" >> $cfg
}

func_validate_parameter_value() {
	case "${2}" in
		-*)
			echo "Invalid value for parameter ${1}: ${2}"
            exit 1
			;;
	esac
}

if [ "$#" -eq 0 ]; then
    func_help
    exit 0
fi

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        # Required
        --out )
            func_validate_parameter_value "${1}" "${2}"
            OUT="${2}"
            shift
            shift
            ;;
        --llvm-path )
            func_validate_parameter_value "${1}" "${2}"
            LLVM_PATH="${2}"
            shift
            shift
            ;;
        # Optional
        --artifact-copy )
            func_validate_parameter_value "${1}" "${2}"
            ARTIFACT_COPY="${2}"
            shift
            shift
            ;;
        --artifact-upload )
            func_validate_parameter_value "${1}" "${2}"
            ARTIFACT_UPLOAD="${2}"
            shift
            shift
            ;;
        --branch )
            func_validate_parameter_value "${1}" "${2}"
            BRANCH="${2}"
            shift
            shift
            ;;
        --cherry-pick )
            func_validate_parameter_value "${1}" "${2}"
            CHERRY_PICK="${2}"
            shift
            shift
            ;;
        --legacy-omx )
            LEGACY_OMX="true"
            shift
            ;;
        --lto )
            LTO="true"
            shift
            ;;
        --partition )
            func_validate_parameter_value "${1}" "${2}"
            PARTITION="${2}"
            shift
            shift
            ;;
        --help )
            func_help
            exit 0
            ;;
        -*)
            echo "Unknown parameter: $1"
            exit 1
            ;;
        *)
            shift
            ;;
    esac
done

if ! [ "$(git branch --list $BRANCH_COMMITS)" ]; then
    echo "Error: Branch $BRANCH_COMMITS does not exist, Which is required."
    exit 1
fi
if ! [ "$(git branch --list $BRANCH_MAIN)" ]; then
    echo "Error: Branch $BRANCH_MAIN does not exist, Which is required."
    exit 1
fi

if [ -z "$OUT" ]; then
    echo "Please specify out directory."
    exit 1
fi
if [ -d "$OUT" ]; then
    OUT="$(realpath $OUT)"
    if ! rm -rf "$OUT"; then
        echo "Failed to cleanup out directory."
        exit 1
    fi
fi
if ! mkdir -p "$OUT"; then
    echo "Failed to create out directory."
    exit 1
fi
if [ -z "$LLVM_PATH" ] || ! [ -f "$LLVM_PATH/bin/clang" ]; then
    echo "LLVM Toolchain path is wrong."
    exit 1
fi
LLVM_PATH="$(realpath $LLVM_PATH)"
if ! [ -z "$ARTIFACT_COPY" ] && ! [ -d "$ARTIFACT_COPY" ]; then
    echo "Artifact copy out directory does not exist."
    exit 1
fi
case "$ARTIFACT_UPLOAD" in
    "oshi.at"|"transfer.sh")
        ;;
    "")
        ;;
    *)
        echo "Unsupported artifact upload site: $ARTIFACT_UPLOAD"
        exit 1
        ;;
esac
if ! [ -z "$BRANCH" ] && ! [ "$(git branch --list $BRANCH)" ]; then
    echo "Error: Specified branch $BRANCH does not exist."
    exit 1
fi
if ! [ -z "$CHERRY_PICK" ]; then
    if ! echo -n "$CHERRY_PICK"|grep -E "^[a-z0-9| ]+$" > /dev/null; then
        echo "Invalid commit ids to cherry-pick: $CHERRY_PICK"
        exit 1
    fi
fi
case "$PARTITION" in
    "boot")
        ;;
    "recovery")
        ;;
    "")
        PARTITION="boot"
        ;;
    *)
        echo "Unsupported partition: $PARTITION"
        exit 1
        ;;
esac

if ! [ -z "$CHERRY_PICK" ]; then
    VARIANT_NAME="TEST"
elif [ "$PARTITION" == "recovery" ]; then
    VARIANT_NAME="Recovery"
elif [ "$LEGACY_OMX" == "true" ]; then
    VARIANT_NAME="LegacyOMX"
else
    VARIANT_NAME=""
fi

git stash save -a "$(date +backup_%Y%m%d-%H%M%S)" || true
if ! [ -z "$BRANCH" ]; then
    git checkout $BRANCH
else
    git checkout $BRANCH_MAIN
fi
git checkout $(git rev-parse --short HEAD)

if ! [ -z "$CHERRY_PICK" ]; then
    if ! eval git cherry-pick $CHERRY_PICK; then
        echo "Failed to cherry-pick specified commits"
        git reset --hard
    fi
fi
if [ "$LEGACY_OMX" == "true" ]; then
    git cherry-pick $(func_get_commitid_by_msg "$COMMITMSG_LEGACY_OMX")
fi
if grep "qcom,qpnp-haptics" arch/arm64/boot/dts/qcom/pmi8950.dtsi>/dev/null; then
    if [ "$PARTITION" == "boot" ]; then
        git revert $(func_get_commitid_by_msg "$COMMITMSG_OLD_VIB_DTS") --no-edit
    fi
else
    if [ "$PARTITION" != "boot" ]; then
        git cherry-pick $(func_get_commitid_by_msg "$COMMITMSG_OLD_VIB_DTS")
    fi
fi

if [ "$PARTITION" == "recovery" ]; then
    sed -i 's|max_brightness = LED_FULL|max_brightness = 1|g' drivers/leds/leds-msm-back-gpio-flash-ulysse.c
    git add drivers/leds/leds-msm-back-gpio-flash-ulysse.c
    git commit -m "Workaround flashlight issue in recovery mode"
fi

cat arch/arm64/configs/mi8937_defconfig arch/arm64/configs/.mi8937_defconfig_extra >> $OUT/.config

source $OUT/.config
if ! [ -z "$VARIANT_NAME" ]; then
    sed -i "s|CONFIG_LOCALVERSION=\"${CONFIG_LOCALVERSION}\"|CONFIG_LOCALVERSION=\"${CONFIG_LOCALVERSION}-${VARIANT_NAME}\"|g" $OUT/.config
fi
echo >> $OUT/.config
echo "# Appended by build script" >> $OUT/.config
if [ "$LTO" == "true" ]; then
    func_set_defconfig $OUT/.config CONFIG_LTO_CLANG y
fi
source $OUT/.config

export ARCH=arm64
export PATH="${LLVM_PATH}/bin:$PATH"
export CROSS_COMPILE="${LLVM_PATH}/bin/aarch64-linux-gnu-"
export CROSS_COMPILE_ARM32="${LLVM_PATH}/bin/arm-linux-gnueabi-"

make O=$OUT $BUILD_FLAGS olddefconfig
make O=$OUT $BUILD_FLAGS

BUILD_DATE_SHORT="$(TZ=UTC date +%Y%m%d)"
KERNEL_VERSION="$(grep 'Kernel Configuration' $OUT/.config | cut -d ' ' -f 3)"
LOCALVERSION="$(echo -n $CONFIG_LOCALVERSION|cut -c 2-)"

mv $OUT/arch/arm64/boot/dts/ $OUT/arch/arm64/boot/dts-orig/
if [ "$PARTITION" == "boot" ]; then
    git cherry-pick $(func_get_commitid_by_msg "$COMMITMSG_OLD_VIB_DTS")
    make O=$OUT $BUILD_FLAGS dtbs
fi

if ! [ -f "$OUT/arch/arm64/boot/Image.gz" ] || ! [ -f "$OUT/arch/arm64/boot/Image.gz-dtb" ]; then
    echo "Kernel binary has not generated"
    exit 1
fi

if [ -d ".ak3_patches" ] && ! [ -z "$(ls .ak3_patches/*.patch)" ]; then
    git am .ak3_patches/*.patch
fi
sed -i "s|REPLACE_KERNEL_STRING|${LOCALVERSION} Kernel ${KERNEL_VERSION}|g" .ak3/anykernel.sh
sed -i "s|REPLACE_PARTITION|${PARTITION}|g" .ak3/anykernel.sh
if [ "$PARTITION" == "boot" ]; then
    sed -i "s|REPLACE_ANDROID_VERSION|${SUPPORTED_ANDROID_VERSIONS}|g" .ak3/anykernel.sh
else
    sed -i "s|REPLACE_ANDROID_VERSION||g" .ak3/anykernel.sh
fi
rm -rf $OUT/pack
cp -r .ak3 $OUT/pack

git add -A || true
git commit -m "Final changes of build on $(date)" || true
FINAL_GIT_HEAD_SHORT="$(git rev-parse --short HEAD)"

cd $OUT/pack
mkdir dtbs-newvib dtbs-oldvib
if [ "$PARTITION" == "boot" ]; then
    mv ../arch/arm64/boot/dts-orig/qcom/*.dtb dtbs-newvib/
    mv ../arch/arm64/boot/dts/qcom/*.dtb dtbs-oldvib/
else
    mv ../arch/arm64/boot/dts-orig/qcom/*.dtb dtbs-oldvib/
fi
mv ../arch/arm64/boot/Image.gz Image.gz
cp ../.config kernel-config.txt
ARTIFACT_NAME="${LOCALVERSION}-Kernel-${KERNEL_VERSION}-${BUILD_DATE_SHORT}-${FINAL_GIT_HEAD_SHORT}.zip"
zip -r9 "../$ARTIFACT_NAME" * -x .git README.md *placeholder *.zip
cd ../

if [ -f "$ARTIFACT_NAME" ]; then
    if [ -d "$ARTIFACT_COPY" ]; then
        cp "$ARTIFACT_NAME" "${ARTIFACT_COPY}/"
    fi
    case "$ARTIFACT_UPLOAD" in
        "oshi.at")
            curl --upload-file "$ARTIFACT_NAME" "https://oshi.at/${ARTIFACT_NAME}" | tee upload.txt
            ;;
        "transfer.sh")
            curl --upload-file "$ARTIFACT_NAME" "https://transfer.sh/${ARTIFACT_NAME}" | tee upload.txt
            ;;
    esac
    if [ -f "upload.txt" ] && [ -d "$ARTIFACT_COPY" ]; then
        cp "upload.txt" "${ARTIFACT_COPY}/"
    fi
fi

exit 0
