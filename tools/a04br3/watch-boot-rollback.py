#!/usr/bin/env python3
"""Restore only a cryptographically identified diagnostic boot on the known USB port."""
import argparse
import datetime
import hashlib
import subprocess
import time
from pathlib import Path
from zoneinfo import ZoneInfo


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--work", type=Path, required=True)
    ap.add_argument("--backup", type=Path, required=True)
    ap.add_argument("--diagnostic", type=Path, required=True)
    ap.add_argument("--preloader", type=Path, required=True)
    ap.add_argument("--usb-port", required=True)
    args = ap.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    for attr in ("work", "backup", "diagnostic", "preloader"):
        setattr(args, attr, getattr(args, attr).resolve())
    original = args.backup.read_bytes()
    expected = args.diagnostic.read_bytes()
    if len(original) != 16777216 or hashlib.sha256(original).hexdigest() != "760cf0d774211d7d705fae1dc2618cadd3fc6be88534410ebd4d5899630093f4":
        raise SystemExit("unexpected rollback backup; refusing all writes")
    port = Path("/sys/bus/usb/devices") / args.usb_port
    end = datetime.datetime(2026, 10, 19, 7, 30, tzinfo=ZoneInfo("Asia/Tokyo"))
    print("Waiting for preloader/BROM on", port, flush=True)
    while datetime.datetime.now(ZoneInfo("Asia/Tokyo")) < end:
        try:
            candidate = port.joinpath("idVendor").read_text().strip() == "0e8d" and port.joinpath("idProduct").read_text().strip() in ("0003", "2000", "2001")
        except OSError:
            candidate = False
        if candidate:
            break
        time.sleep(5)
    else:
        print("No supported boot transport appeared before 07:30; no write performed", flush=True)
        return

    def run(*command):
        print("MTK action:", command[0], flush=True)
        with (args.work / "mtk.log").open("ab") as log:
            subprocess.run(["mtk", *map(str, command), "--preloader", str(args.preloader)], cwd=args.work, stdout=log, stderr=subprocess.STDOUT, timeout=180, check=True)

    before = args.work / "boot-before.img"
    run("r", "boot", before)
    actual = before.read_bytes()
    if len(actual) != len(original) or actual[:len(expected)] != expected:
        raise SystemExit("diagnostic boot identity mismatch; no write performed")
    run("w", "boot", args.backup)
    after = args.work / "boot-after.img"
    run("r", "boot", after)
    if after.read_bytes() != original:
        raise SystemExit("rollback readback mismatch; do not report recovery")
    print("Original boot fully verified; requesting reset", flush=True)
    run("reset")


if __name__ == "__main__":
    main()
