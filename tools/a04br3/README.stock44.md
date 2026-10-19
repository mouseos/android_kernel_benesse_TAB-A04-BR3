# Isolated product-derived 4.4 FM control

This is an experiment, not a release or a completed FM validation.
The product-derived source snapshot is published on branch
fm-stock44-20261019 of mouseos/android_kernel_benesse_TAB-A04-BR3.
The imported copy includes prior GSI kernel work; it is not claimed to be
an unmodified stock kernel. AOSP and reference BSP files are not edited.

Use unmodified AOSP android-10.0.0_r47 for the host toolchain and obtain
GCC 4.9 from the GitHub repository
LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9,
cm-14.1 commit 7280ce2399316a5dbd8872e0bfe69435d8719230.

Set AOSP, STOCK44_SRC, dedicated STOCK44_OUT, and STOCK44_GCC_PREFIX to
the absolute GCC bin/aarch64-linux-android- prefix. Set STOCK44_CONFIGFS=1
and run build-stock44-diagnostic.sh. KERNEL_JOBS defaults to 4.
This enables FM, MT6630_FM, configfs/FFS/MTP/PTP, and Magic SysRq; legacy
Android USB is disabled. The charger source has a conditional MUSB cable
query in the configfs configuration instead of the legacy android gadget
singleton. The legacy configuration is unchanged.

Repackage a known-good release MTK v0 boot with:

```sh
python3 repack-diagnostic-boot.py --base boot-known-good.img \
 --kernel "$STOCK44_OUT/arch/arm64/boot/Image.gz-dtb" \
 --uart-console --output boot-stock44-diagnostic.img
```

The ramdisk is preserved. --uart-console changes both the kernel console
argument and androidboot.console to ttyMT0. Without that option, the
current release kernel reproduces release boot SHA f2632aba2d848b1d34fae6e2b853f22c9bf77641dd88f8890c99ccc0567694cd.
The script validates format and 16MiB partition capacity; it does not flash.

## Device result and incident

The initial 4.4 legacy-USB build booted and initialized WMT and the FM
device. Its kernel SHA was f1a8574a2b4cc527528103fd90498217323d27328452b1822fc255f2ba5c0dfa.
That test boot preserved a 4.14 ttyS0 argument and lacked configfs.
The Android 10 USB/console path then became unavailable. UART logs are
still received, but no FM command execution has been confirmed.
This is not an FM success or a completed control test. The mismatch
should have been caught before writing the initial test image.

The backup remains on host and device. The device has not yet been restored.
Before another boot experiment, establish and validate a timed rollback
service and explicit ttyMT0 console. The USB rollback watcher in this tools
directory is for the specific recorded test only: known physical USB port,
known exact diagnostic boot bytes, fixed 16MiB backup SHA, read-before-write
identity check, and full restore readback. It cannot reset the running device
or create a USB connection. Do not describe an armed watcher as recovery.

The user forbids asking for device operations before 07:30 JST on 2026-10-19.
At 03:00, switch to GSI testing if FM is impossible or has made no progress.
Keep these timing rules in the live goal record rather than treating this
historical README as a future schedule.

## Completed recovery and one-shot comparison procedure

The original 4.14 boot has now been restored and verified on hardware.
Use fm-control-once.rc and fm-control-once.sh as temporary vendor init
files. First boot the original kernel and require validation-passed.
The 4.4 branch restores and hashes the complete original boot before any
FM ioctl, then runs a bounded receive test and reboots to the original.
A separate 150-second reboot process bounds a blocked ioctl. This does
not protect failures before post-fs-data or a completely locked kernel.

The current Android 10 camera HAL triggers a kernel NULL dereference in
4.4 feature_control. Back up /vendor/etc/init/camerahalserver.rc and add
its disabled option temporarily for this control; restore it afterwards.
The 4.4 FM tune ABI lacks the newer deemphasis byte: build its test with
aarch64-linux-gnu-gcc -static -DFM_PRODUCT44 -O2 -Wall -Wextra
tools/a04br3/fm-test.c -o fm-test-stock44 and install as
/data/local/tmp/a04br3-fm-test-stock44. The normal 4.14 test is unchanged.
Remove the temporary service/script and restore the camera rc after testing.

## FM control outcome

The former pending statements are historical. The corrected 4.4 kernel
was booted and the receive helper executed with both WMT20200515 and
product WMT20190702. Existing WMT FM operations must be included using
fm-stock44-20261019 commit47da57a8; the original product's unconfigured
CONFIG_MTK_COMBO_FM gate otherwise leaves function1 without operations.

Both firmware pairs reached ROM and DSP image download, but POWERUP
returned errno1005 at tune. Traces retain the same opcode0x22/e803
initialization symptom. The one-shot service restored the full original
16MiB boot and verified SHA760cf0d774211d7d705fae1dc2618cadd3fc6be88534410ebd4d5899630093f4
before each trial, then automatically rebooted to 4.14.141+ #18.
No receiver success or hardware-cause certainty is claimed.
