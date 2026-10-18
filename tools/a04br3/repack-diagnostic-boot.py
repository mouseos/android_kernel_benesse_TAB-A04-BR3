#!/usr/bin/env python3
"""Repackage a v0 MTK boot with a source-built kernel; preserve its ramdisk."""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base", type=Path, required=True)
    ap.add_argument("--kernel", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--uart-console", action="store_true", help="Use ttyMT0 for the product 4.4 UART")
    args = ap.parse_args()
    image = args.base.read_bytes()
    kernel = args.kernel.read_bytes()
    if image[:8] != b"ANDROID!":
        raise SystemExit("invalid base boot magic")
    ksz, _, rsz, _, ssz, _, _, page, version = struct.unpack_from("<9I", image, 8)
    if version or ssz or page not in (2048, 4096):
        raise SystemExit("requires v0 boot, no second stage, 2K/4K page")
    roff = page + ((ksz + page - 1) // page) * page
    ramdisk = image[roff:roff + rsz]
    if len(ramdisk) != rsz or len(kernel) < 1000000:
        raise SystemExit("truncated input")
    if struct.unpack_from("<I", ramdisk)[0] != 0x58881688:
        raise SystemExit("base ramdisk must have an MTK header")
    if struct.unpack_from("<I", kernel)[0] == 0x58881688:
        raise SystemExit("kernel already has an MTK header")
    kernel = struct.pack("<II32s", 0x58881688, len(kernel), b"KERNEL") + b"\xff" * 472 + kernel
    header = bytearray(image[:page])
    struct.pack_into("<I", header, 8, len(kernel))
    if args.uart_console:
        cmdline = (bytes(header[64:576]) + bytes(header[608:1632])).split(b"\0", 1)[0].decode()
        cmdline = re.sub(r"console=ttyS0(?:,[^ ]+)?", "console=ttyMT0,921600n1", cmdline)
        cmdline = re.sub(r"androidboot.console=[^ ]+", "", cmdline)
        encoded = (cmdline.strip() + " androidboot.console=ttyMT0").encode()
        if len(encoded) >= 1536:
            raise SystemExit("command line too long")
        encoded = encoded.ljust(1536, b"\0")
        header[64:576] = encoded[:512]
        header[608:1632] = encoded[512:]

    sha = hashlib.sha1()
    for data in (kernel, ramdisk, b""):
        sha.update(data)
        sha.update(struct.pack("<I", len(data)))
    header[576:608] = sha.digest().ljust(32, b"\0")
    pad = lambda data: data + b"\0" * (-len(data) % page)
    output = bytes(header) + pad(kernel) + pad(ramdisk)
    if len(output) > 16 * 1024 * 1024:
        raise SystemExit("boot exceeds the 16MiB partition")
    args.output.write_bytes(output)
    print(json.dumps({"output": str(args.output), "bytes": len(output),
                      "sha256": hashlib.sha256(output).hexdigest(),
                      "ramdisk_sha256": hashlib.sha256(ramdisk).hexdigest(),
                      "base_sha256": hashlib.sha256(image).hexdigest()}, indent=2))


if __name__ == "__main__":
    main()
