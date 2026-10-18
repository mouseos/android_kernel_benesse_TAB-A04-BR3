#!/usr/bin/env bash
# Build the TAB-A04-BR3 kernel and its MT6630 connectivity modules with the
# toolchains of an AOSP 10 checkout (the compiler versions the MT8167 BSP uses).
#
#   AOSP=<AOSP 10 top> ./build-a04br3.sh [<device tree dir>]
#
# Output (A04BR3_KERNEL_OUT, default ../a04br3-kernel-out):
#   dist/Image.gz-dtb, dist/modules/*.ko
# With a device tree dir (device/benesse/a04br3) the result is also copied to
# its prebuilt/ directory.
#   KERNEL_JOBS  parallel jobs (default: number of CPUs)
set -euo pipefail

src=$(cd "$(dirname "$0")" && pwd)
: "${AOSP:?set AOSP to the top of an AOSP 10 checkout (for prebuilts/)}"
aosp=$(cd "$AOSP" && pwd)
out=${A04BR3_KERNEL_OUT:-$src/../a04br3-kernel-out}
mkdir -p "$out"
out=$(cd "$out" && pwd)
jobs=${KERNEL_JOBS:-$(nproc)}
device_dir=${1:-}

prebuilts="$aosp/prebuilts"
clang_dir="$prebuilts/clang/host/linux-x86/clang-r353983c/bin"
gcc_prefix="$prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-"
host_gcc="$prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/bin/x86_64-linux-"
for f in "$clang_dir/clang" "${gcc_prefix}ld" "${host_gcc}gcc"; do
    [[ -x "$f" ]] || { echo "missing toolchain: $f" >&2; exit 1; }
done

kout="$out/obj"
make_args=(-C "$src" O="$kout" ARCH=arm64
    CROSS_COMPILE="$gcc_prefix" CLANG_TRIPLE=aarch64-linux-gnu-
    CC="$clang_dir/clang" HOSTCC="${host_gcc}gcc" HOSTCXX="${host_gcc}g++"
    KBUILD_BUILD_USER=build KBUILD_BUILD_HOST=tab-a04-br3)

echo "=== $(date '+%F %T') kernel $(git -C "$src" describe --always --dirty 2>/dev/null || echo unknown) jobs=$jobs"
make "${make_args[@]}" a04br3_defconfig
make "${make_args[@]}" -j"$jobs" Image.gz-dtb

# External connectivity modules (MT6630), built like the BSP's build_ko.mk:
# a private copy of each source tree, M= against the kernel output, and the
# Module.symvers of the modules it depends on.
mod_out="$out/modules"
mod_src="$src/modules/connectivity"
rm -rf "$mod_out" "$out/dist"
mkdir -p "$out/dist/modules"
# The module Makefiles include headers from
# $(TOP)/vendor/mediatek/kernel_modules/connectivity, i.e. the BSP layout.
mkdir -p "$mod_out/top/vendor/mediatek/kernel_modules"
ln -s "$mod_src" "$mod_out/top/vendor/mediatek/kernel_modules/connectivity"
mod_vars=(TOP="$mod_out/top" KERNEL_OUT="$kout" MTK_PLATFORM=mt8167 MTK_PROJECT=a04br3 TARGET_BUILD_VARIANT=userdebug
    AUTOCONF_H="$kout/include/generated/autoconf.h")
build_mod() { # name source-dir dependency-names...
    local name=$1 dir=$2; shift 2
    local work="$mod_out/$name" syms=()
    mkdir -p "$work"
    cp -a "$mod_src/$dir/." "$work/"
    for dep in "$@"; do syms+=("$mod_out/$dep/Module.symvers"); done
    make "${make_args[@]}" -j"$jobs" M="$work" "${mod_vars[@]}" \
        ${syms:+KBUILD_EXTRA_SYMBOLS="${syms[*]}"} modules
    "${gcc_prefix}strip" --strip-debug -o "$out/dist/modules/$name.ko" "$work/$name.ko"
}
build_mod wmt_drv common
build_mod wmt_chrdev_wifi wlan/adaptor wmt_drv
build_mod wlan_drv_gen3 wlan/core/gen3 wmt_drv wmt_chrdev_wifi
build_mod bt_drv bt/mt66xx/legacy wmt_drv
# MT6630 FM (CONFIG_MTK_FMRADIO=y, CONFIG_MTK_FM_CHIP="MT6630_FM" in a04br3_defconfig)
build_mod fmradio_drv fmradio wmt_drv
cp "$kout/arch/arm64/boot/Image.gz-dtb" "$out/dist/Image.gz-dtb"

if [[ -n "$device_dir" ]]; then
    mkdir -p "$device_dir/prebuilt/modules"
    cp "$out/dist/Image.gz-dtb" "$device_dir/prebuilt/Image.gz-dtb"
    rm -f "$device_dir/prebuilt/modules/"*.ko
    cp "$out/dist/modules/"*.ko "$device_dir/prebuilt/modules/"
fi
echo "=== $(date '+%F %T') done"
ls -l "$out/dist" "$out/dist/modules"
