#!/usr/bin/env bash
# Build the separate product-derived 4.4 source with FM enabled.
set -euo pipefail
: "${AOSP:?set AOSP}"
: "${STOCK44_SRC:?set STOCK44_SRC to the product-derived 4.4 source}"
: "${STOCK44_OUT:?set a dedicated STOCK44_OUT}"
mkdir -p "$STOCK44_OUT"
src=$(cd "$STOCK44_SRC" && pwd)
out=$(cd "$STOCK44_OUT" && pwd)
aosp=$(cd "$AOSP" && pwd)
prefix=${STOCK44_GCC_PREFIX:-"$aosp/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"}
[[ -x "${prefix}gcc" ]] || { echo "set STOCK44_GCC_PREFIX to a GCC 4.9 toolchain" >&2; exit 1; }
host="$aosp/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/bin/x86_64-linux-"
args=(-C "$src" O="$out" ARCH=arm64 CROSS_COMPILE="$prefix" HOSTCC="${host}gcc" HOSTCXX="${host}g++" KBUILD_BUILD_USER=build KBUILD_BUILD_HOST=tab-a04-br3)
make "${args[@]}" a04br3_defconfig
"$src/scripts/config" --file "$out/.config" --enable MTK_FMRADIO --set-str MTK_FM_CHIP MT6630_FM
if [[ ${STOCK44_CONFIGFS:-0} == 1 ]]; then
    "$src/scripts/config" --file "$out/.config" --enable MAGIC_SYSRQ --disable USB_G_ANDROID \
        --enable USB_CONFIGFS --enable USB_CONFIGFS_F_FS --enable USB_CONFIGFS_F_MTP \
        --enable USB_CONFIGFS_F_PTP --enable USB_CONFIGFS_UEVENT
fi
make "${args[@]}" olddefconfig
make "${args[@]}" -j"${KERNEL_JOBS:-4}" Image.gz-dtb
sha256sum "$out/arch/arm64/boot/Image.gz-dtb"
