"""Compare APK payloads independently of randomized signing-block bytes."""

import hashlib
import sys
import zipfile


def payload(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError(f"Duplicate ZIP entry in {path}")
        result = {}
        for name in names:
            with archive.open(name) as entry:
                result[name] = hashlib.file_digest(entry, "sha256").hexdigest()
        return result


def compare(original, rebuilt):
    first, second = payload(original), payload(rebuilt)
    differences = sorted(
        name for name in first.keys() | second.keys()
        if first.get(name) != second.get(name)
    )
    if differences:
        raise ValueError("APK payload mismatch: " + ", ".join(differences))
    return len(first)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: compare_apks.py ORIGINAL.apk REBUILT.apk")
    try:
        print(f"OK all {compare(*sys.argv[1:])} APK entries match (SHA-256)")
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        sys.exit(str(error))
