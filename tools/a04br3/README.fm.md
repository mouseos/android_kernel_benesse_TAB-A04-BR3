# MT6630 FM diagnostic experiment

This branch is experimental. FM reception has NOT been demonstrated.
AOSP android-10.0.0_r47 and the reference BSP must remain unmodified.

Build the kernel/WMT outputs with the repository build-a04br3.sh first.
For incremental FM builds, set AOSP and A04BR3_KERNEL_OUT to those same
absolute directories and run tools/a04br3/build-fm.sh. It does not copy
experimental modules into device prebuilts. No reference BSP is required.
Build the static ARM64 test with:

```sh
aarch64-linux-gnu-gcc -static -O2 -Wall -Wextra tools/a04br3/fm-test.c -o fm-test
```

Use a rooted userdebug device. Preserve the current module and firmware.
Push the resulting fmradio_drv.ko and fm-test to /data/local/tmp, unload
fmradio_drv while idle, then load the new module with fm_rx_trace=1.
The parameter defaults to false; its only change is raw receive logging.
Run fm-test 8000 0 for 80.0 MHz. Save dmesg and UART before rebooting.
The test requests receive operations only and powers FM down on exit.
This test needs the vendor FM patch/coeff blobs; they are NOT supplied by
this source-only diagnostic directory. It is not a complete FM release.

## 2026-10-19 device evidence

TAB-A04-BR3, MT6630 package strap 1, kernel 4.14.141+ #18.
The module builds and loads on the USB-fixed kernel without rewriting boot.
Baseline and raw tracing both failed FM_IOCTL_POWERUP with error 1005.
The power-up path prints success, then tuning times out. An automatic
subsystem recovery repeats the sequence. Raw trace before enable completion:

```text
FM RX: 04 22 02 00 e8 03 04 07 00 00
```

This is a two-byte event payload 0x03e8 preceding enable completion, also
seen in earlier Armbian investigations. The BSP header names opcode 0x22
FM_HOST_MODIFY_OPCODE; do not implement generic error handling from the
payload alone without verifying the actual firmware event contract.
The trace is evidence of the failure stage, not proof of hardware omission.
No reception, audio or RDS was obtained. Firmware and boot were unchanged.
Prior Hennessy WMT substitution failed combo initialization in Armbian;
that is not evidence that all firmware alternatives are exhausted.

## Independent readback and stock WMT comparison

The TAB-A04-BR3 stock Android 7 build 01.06.000 contains 20190702 WMT
patches. Normal Android 10 BSP inputs use 20200515. Swapping only the two
stock patches, rebooting, and rerunning the same test still returned 1005
and the same raw 0x22 event. Stock patches initialized successfully. The
BSP pair was restored and verified by hash and by its boot-time timestamp.

An optional second module parameter, fm_verify_init=1, snapshots FM and
host registers after digital init and requires the exact condition used
by the existing BOP: (reg[0x64] & 0x1f) == 2. It defaults to false.
For that test, load the module with both fm_rx_trace=1 fm_verify_init=1.
Readback on the restored BSP firmware showed:

| Register | Value |
| --- | --- |
| FM 60,61,62,64,83,84 | 0000 (all reads returned 0) |
| host 8102123c | 741fee1e |
| host 81021134 | 03807886 |
| host 81020010 | 0000c00f |
| host 81021430 | 80000187 |
| host 81020008 | 00030033 |
| host 80000108 | 00000000 |

The last register is an enable-write address from the stock sequence;
its zero readback alone does not establish actual clock-gate status.
The optional check returned EIO before tune, avoiding the misleading
power-up success message. This is a diagnostic improvement, not an FM fix.
No actual reception was observed. AOSP, reference BSP, main and release
artifacts were unchanged. The boot partition hash remained unchanged.

Comparison with the project copy of the product 4.4 MT6630 driver, after
normalizing integer typedefs, found identical top-power, clock-on,
ROM handshake, DSP transfer and digital-init operations. The ECO version
query differs (metadata only); the patch is selected by FM ROM version.
This source comparison is not an independent stock-kernel boot test.
