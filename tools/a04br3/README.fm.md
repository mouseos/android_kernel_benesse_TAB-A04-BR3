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

## RTC state and remaining evidence boundary

Read-only Android PMIC regmap checks at RTC base 0x8000 returned:
RTC_PDN1 (0x802c) = 0x0200 and RTC_CON (0x803e) = 0x0407.
The GPS/connectivity user bit is set and F32KOB (bit 5) is clear.
This proves the software request, not a waveform at the MT6630 ball.
The source locations are drivers/mfd/mt6397-core.c (MT6392_RTC_BASE)
and drivers/mfd/mt6397-misc.c (RTC_PDN1/RTC_CON and enable sequence).
With this regmap's 16-bit register/value format and stride 2, a record is
11 bytes. The checks used seekable debugfs reads of only the two records:

```sh
dd if=/sys/kernel/debug/regmap/1000f000.pwrap/registers bs=11 skip=16406 count=1
dd if=/sys/kernel/debug/regmap/1000f000.pwrap/registers bs=11 skip=16415 count=1
```

Validate the printed addresses; do not assume those offsets for a different
regmap layout. No PMIC write was issued.

MT6630QA external datasheet v1.14a, section 4.1 (PDF page 31), describes
automatic internal-32K fallback but also requires host-supplied XTAL
frequency information in that mode. The MT6630-specific public driver
path for that second condition is not established here. Blindly disabling
RTC is not a valid completed internal-clock A/B test. QP applicability is
also unverified; the attached chip datasheet describes QA.

Prior Armbian evidence covers page-F reselection, host-driven Digital Init,
normal and disabled DSP patch execution, 256-byte DSP segmentation,
MRG/I2S bypass, old/new top-power sequences, post-transfer ROM handshake,
RTC request order, FM strap/DAI and WMT bootstrap comparisons. None of those
is a fresh untested fix to rerun without a new discrepancy. The stock WMT
substitution and Android readback in this branch provide independent stack
checks, not an exclusion of every software cause.

The practical evidence boundary is physical FM supply/clock delivery versus
an undocumented image-specific startup condition or silicon configuration.
The current microscopic photos do not prove the relevant nets are absent.
There is no defensible quantitative basis for a 99% hardware-omission claim.
Useful new inputs are a QP/board schematic identifying AVDD33_FM and RTCCLK,
measurements at those nets, or an MT6630-specific documented internal-32K
frequency setup sequence. This is an unresolved FM bring-up result.

## Pending analog-path initialization comparison

The previous Armbian skip_i2s_setup parameter only bypasses I2S register
setup. Its clock-on builder still tests aud_path and selects bit 7 of
register 0x61 for every path other than FM_AUD_ANALOG. Skipping setup is
therefore not equivalent to selecting analog output. No completed analog
mode test was found in the reviewed summaries/source history; that is a
bounded search, not a claim that every historical raw log was searched.

The optional read-only module parameter fm_analog_init_test=1 selects the
stock FM_AUD_ANALOG path before clock-on. The existing builder then clears
0x61 bit 7 and skips I2S/MRG setup. No new register definition or guessed
WMT command is introduced. Default false preserves normal behavior.
The WMT FM communication strap is deliberately unchanged; it is not
established as an audio-mode selector.

For a controlled comparison, first restore the known 4.14 #18 environment.
This module cannot load into the current experimental 4.4 kernel. Load it
with fm_rx_trace=1 fm_verify_init=1 fm_analog_init_test=1, then use fm-test
8000 0 and retain raw events and the ready-state readback. Compare with the
recorded normal-path baseline. This diagnoses DSP initialization; analog
output has not been routed to the board speaker, and a ready/tune return
alone is not demonstrated radio reception.

The diagnostic module built successfully, SHA256
14c80ac879f07d7ace143dc1c7ceb149486391129253fd55f3db1b3304c42b01.
It has NOT been loaded or tested on hardware because device control is
still unavailable. Hardware omission remains unproven. Do not mark this
hypothesis rejected merely because the different I2S-bypass test failed.
