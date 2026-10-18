#!/usr/bin/env bash
# Build the standard AOSP 10 arm64 userdebug GSI without source patches.
set -euo pipefail
: "${GSI_ROOT:?set GSI_ROOT to the workspace containing aosp/ and build/}"
root=$(cd "$GSI_ROOT" && pwd)
jobs=${AOSP_JOBS:-4}
mkdir -p "$root/build/gsi-userdebug-out" "$root/build/host-libs"
for lib in libncurses.so.5 libtinfo.so.5; do
 ln -sfn "/mnt/aosp/prebuilts/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/sysroot/usr/lib/$lib" "$root/build/host-libs/$lib"
done
exec unshare -Ur -m bash -s -- "$root" "$(id -u)" "$(id -g)" "$jobs" <<'INNER'
set -euo pipefail
root=$1 uid=$2 gid=$3 jobs=$4
mount --bind "$root" /mnt
cd /mnt/aosp
exec unshare --map-user="$uid" --map-group="$gid" bash -c '
set -eo pipefail
export OUT_DIR=/mnt/build/gsi-userdebug-out
export BUILD_USERNAME=build BUILD_HOSTNAME=tab-a04-br3
export NINJA_HIGHMEM_NUM_JOBS=1 SKIP_ABI_CHECKS=true
export LD_LIBRARY_PATH=/mnt/build/host-libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
source build/envsetup.sh >/dev/null
lunch aosp_arm64-userdebug
m -j"$1" systemimage
' bash "$jobs"
INNER
