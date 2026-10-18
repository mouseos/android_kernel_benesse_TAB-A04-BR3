#!/usr/bin/env python3
"""Inventory vendor DT_NEEDED names against a GSI; no execution or ABI proof."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--vendor", type=Path, required=True)
    ap.add_argument("--gsi", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("roots", nargs="+")
    args = ap.parse_args()
    args.vendor = args.vendor.resolve()
    inventory = {}
    listing_errors = []
    for bits, lib in [(64, "lib64"), (32, "lib")]:
        inventory[bits] = {}
        for directory in [f"/system/{lib}", f"/system/{lib}/vndk-29", f"/system/{lib}/vndk-sp-29", f"/system/{lib}/bootstrap", f"/system/apex/com.android.runtime.release/{lib}/bionic", f"/system/apex/com.android.runtime.release/{lib}"]:
            result = subprocess.run(["debugfs", "-R", "ls -p " + directory, str(args.gsi)], capture_output=True, text=True, check=False)
            if "File not found" in result.stderr:
                listing_errors.append(directory)
            for line in result.stdout.splitlines():
                parts = line.split("/")
                if len(parts) >= 7 and ".so" in parts[5]:
                    inventory[bits].setdefault(parts[5], []).append(directory + "/" + parts[5])
    nodes = []
    seen = set()
    queue = [args.vendor / x for x in args.roots]
    missing = []
    while queue:
        path = queue.pop(0)
        if path in seen:
            continue
        seen.add(path)
        data = path.read_bytes()
        if data[:4] != b"\x7fELF" or data[4] not in (1, 2):
            raise SystemExit("not a supported ELF: " + str(path))
        bits = 64 if data[4] == 2 else 32
        lib = "lib64" if bits == 64 else "lib"
        result = subprocess.run(["readelf", "-d", str(path)], capture_output=True, text=True, check=True)
        needed = re.findall(r"\(NEEDED\).*?\[(.*?)\]", result.stdout)
        edges = []
        for name in needed:
            candidates = [args.vendor / lib / name, args.vendor / lib / "hw" / name, args.vendor / lib / "egl" / name]
            present = [p for p in candidates if p.is_file()]
            system = inventory[bits].get(name, [])
            edge = {"name": name, "vendor_candidates": [str(p.relative_to(args.vendor)) for p in present], "gsi_candidates": system}
            if present:
                queue.append(present[0])
            elif not system:
                missing.append({"from": str(path.relative_to(args.vendor)), "needed": name, "bits": bits})
            edges.append(edge)
        nodes.append({"path": str(path.relative_to(args.vendor)), "bits": bits, "sha256": hashlib.sha256(data).hexdigest(), "needed": edges})
    output = {"roots": args.roots, "vendor": str(args.vendor), "gsi": str(args.gsi), "nodes": nodes, "unlocated_names": missing, "missing_inventory_directories": listing_errors, "limitations": ["Ordinary GNU readelf observations, not native execution or REA decompilation.", "System and VNDK dependency recursion is not covered.", "Namespace access, symbol versions, relocations, dlopen targets and kernel interfaces remain unverified.", "Vendor candidates use base/hw/egl lookup for inventory only; this is not Android linker resolution."]}
    args.output.write_text(json.dumps(output, indent=2) + "\n")
    print(json.dumps({"nodes": len(nodes), "unlocated_names": missing, "missing_inventory_directories": listing_errors}))


if __name__ == "__main__":
    main()
