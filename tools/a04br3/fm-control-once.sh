#!/system/bin/sh
# One-shot product-kernel comparison, restoring known-good boot before testing.
BASE=/data/local/tmp/fm-control
mkdir -p "$BASE"
exec >> "$BASE/run-$(uname -r).log" 2>&1
log() { echo "$*"; echo "FMCONTROL $*" > /dev/kmsg; }
GOOD=760cf0d774211d7d705fae1dc2618cadd3fc6be88534410ebd4d5899630093f4
BACK=/data/local/tmp/boot-fm-start.img
BOOT=/dev/block/by-name/boot
log "start kernel=$(uname -r)"
[ "$(sha256sum "$BACK" | cut -d' ' -f1)" = "$GOOD" ] || { log backup-invalid; exit 1; }
case "$(uname -r)" in
  4.14*)
    [ "$(sha256sum "$BOOT" | cut -d' ' -f1)" = "$GOOD" ] || exit 1
    log validation-passed
    touch "$BASE/validated"
    exit 0;;
  4.4*) ;;
  *) log unexpected-kernel; exit 1;;
esac
dd if="$BACK" of="$BOOT" bs=1048576 conv=fsync || exit 1
[ "$(sha256sum "$BOOT" | cut -d' ' -f1)" = "$GOOD" ] || { log restore-failed; exit 1; }
log boot-restored-verified
# A separate process returns to the restored kernel even if the ioctl blocks.
( sleep 150; echo 'FMCONTROL deadline-reboot' > /dev/kmsg; sync; echo b > /proc/sysrq-trigger ) &
DEADMAN=$!
i=0
while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$i" -lt 60 ]; do sleep 1; i=$((i+1)); done
log "test-start boot_completed=$(getprop sys.boot_completed)"
ls -l /dev/fm
cat /proc/modules
timeout -s KILL 45 /data/local/tmp/a04br3-fm-test 8000 0
RESULT=$?
log "test-exit=$RESULT"
dmesg > "$BASE/dmesg-4.4.txt"
sync
kill "$DEADMAN"
log return-to-original
setprop sys.powerctl reboot
sleep 10
echo b > /proc/sysrq-trigger
