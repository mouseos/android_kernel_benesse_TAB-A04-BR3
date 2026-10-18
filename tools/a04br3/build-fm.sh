#!/usr/bin/env bash
# Incremental FM-only build after build-a04br3.sh prepared the kernel and WMT.
set -euo pipefail
src=$(cd "$(dirname "$0")/../.." && pwd)
: "${AOSP:?set AOSP to an unmodified AOSP 10 checkout}"
: "${A04BR3_KERNEL_OUT:?set A04BR3_KERNEL_OUT to the prepared kernel output}"
aosp=$(cd "$AOSP" && pwd)
out=$(cd "$A04BR3_KERNEL_OUT" && pwd)
work="$out/modules/fmradio_drv"
mkdir -p "$work" "$out/dist/modules"
cp -a "$src/modules/connectivity/fmradio/." "$work/"
pre="$aosp/prebuilts"
gcc="$pre/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
host="$pre/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/bin/x86_64-linux-"
make -C "$src" O="$out/obj" ARCH=arm64 CROSS_COMPILE="$gcc" \
 CLANG_TRIPLE=aarch64-linux-gnu- CC="$pre/clang/host/linux-x86/clang-r353983c/bin/clang" \
 HOSTCC="${host}gcc" HOSTCXX="${host}g++" \
 M="$work" TOP="$out/modules/top" KERNEL_OUT="$out/obj" \
 MTK_PLATFORM=mt8167 MTK_PROJECT=a04br3 TARGET_BUILD_VARIANT=userdebug \
 AUTOCONF_H="$out/obj/include/generated/autoconf.h" \
 KBUILD_EXTRA_SYMBOLS="$out/modules/wmt_drv/Module.symvers" \
 -j"${KERNEL_JOBS:-4}" modules
"${gcc}strip" --strip-debug -o "$out/dist/modules/fmradio_drv.ko" "$work/fmradio_drv.ko"
