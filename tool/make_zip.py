#!/usr/bin/env python3
"""Builds a deterministic zip: fixed entry dates, sorted order, no extra metadata.

PowerShell's Compress-Archive writes non-deterministic metadata, so two runs of
the same build produce different zips. This script walks the source in sorted
order and writes every entry with a fixed timestamp, making the archive
bit-for-bit reproducible.

Usage: python tool/make_zip.py <source dir> <output zip>
"""
import os
import sys
import zipfile

_FIXED = (1980, 1, 1, 0, 0, 0)

def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(src):
            dirs.sort()
            files.sort()
            for name in files:
                path = os.path.join(root, name)
                arc = os.path.relpath(path, src).replace(os.sep, "/")
                info = zipfile.ZipInfo(arc, _FIXED)
                info.compress_type = zipfile.ZIP_DEFLATED
                # Regular file, unix permissions 0644 (Windows ignores this).
                info.external_attr = 0o100644 << 16
                with open(path, "rb") as fh:
                    z.writestr(info, fh.read())
    print(f"wrote {dst}")

if __name__ == "__main__":
    main()
