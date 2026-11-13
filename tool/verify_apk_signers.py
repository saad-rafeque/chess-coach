"""Verify APK signatures and compare certificate identities, with useful errors."""

import re
import subprocess
import sys


CERTIFICATE = re.compile(
    r"^Signer (?P<label>#[0-9]+|\([^\r\n]+\)) certificate SHA-256 digest: "
    r"(?P<digest>[0-9a-fA-F]{64})$",
    re.MULTILINE,
)


def certificates(output):
    # apksigner has numbered and SDK-range signer labels (v3.1 rotation).
    # Compare identities AND their labels; never accept an empty extraction.
    records = sorted(
        (match["label"], match["digest"].lower())
        for match in CERTIFICATE.finditer(output.replace("\r\n", "\n"))
    )
    if not records or len(records) != len(set(records)):
        raise ValueError("Missing or duplicate signer certificate records:\n" + output)
    return records


def verified_certificates(apksigner, apk):
    result = subprocess.run(
        [str(apksigner), "verify", "--print-certs", str(apk)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    if result.returncode:
        raise ValueError(f"Signature verification failed for {apk} (exit {result.returncode}):\n{result.stdout}")
    return certificates(result.stdout)


def compare(apksigner, original, rebuilt):
    first = verified_certificates(apksigner, original)
    second = verified_certificates(apksigner, rebuilt)
    if first != second:
        raise ValueError(f"APK signing certificates differ: {first!r} != {second!r}")
    return first


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("Usage: verify_apk_signers.py APKSIGNER ORIGINAL.apk REBUILT.apk")
    try:
        for label, digest in compare(*sys.argv[1:]):
            print(f"OK verified signer {label}: {digest}")
    except (OSError, ValueError) as error:
        sys.exit(str(error))
