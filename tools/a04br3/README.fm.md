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
