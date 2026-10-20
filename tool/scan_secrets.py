#!/usr/bin/env python3
"""Find common credential formats without ever printing their values.

This is a lightweight guard for the private/free GitHub plan, where native secret
scanning is unavailable. It scans the working tree and, by default, reachable Git
history. It is not a replacement for provider-side secret scanning.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path


PATTERNS = {
    "private key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    "GitHub token": re.compile(rb"\bgh[pousr]_[A-Za-z0-9_]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{40,}\b"),
    "Google API key": re.compile(rb"\bAIza[0-9A-Za-z_-]{30,}\b"),
    "Google OAuth secret": re.compile(rb"\bGOCSPX-[A-Za-z0-9_-]{20,}\b"),
    "Google refresh token": re.compile(rb"(?<![A-Za-z0-9])1//0[A-Za-z0-9._-]{30,}"),
    "AWS access key": re.compile(rb"\bAKIA[0-9A-Z]{16}\b"),
    "Slack token": re.compile(rb"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"),
}


def findings(data: bytes) -> list[str]:
    return [name for name, pattern in PATTERNS.items() if pattern.search(data)]


def run_git(*args: str, cwd: Path) -> bytes:
    return subprocess.check_output(["git", *args], cwd=cwd, stderr=subprocess.DEVNULL)


def working_tree(root: Path) -> list[tuple[str, bytes]]:
    names = run_git("ls-files", "--cached", "--others", "--exclude-standard", "-z", cwd=root)
    found = []
    for raw in names.split(b"\0"):
        if not raw:
            continue
        rel = raw.decode("utf-8", "surrogateescape")
        path = root / rel
        if path.is_symlink() or not path.is_file():
            continue
        try:
            found.append((rel, path.read_bytes()))
        except OSError:
            continue
    return found


def history(root: Path) -> list[tuple[str, bytes]]:
    objects = run_git("rev-list", "--objects", "--all", cwd=root).decode().splitlines()
    seen: set[str] = set()
    found = []
    for row in objects:
        parts = row.split(" ", 1)
        oid = parts[0]
        if oid in seen:
            continue
        seen.add(oid)
        path = parts[1] if len(parts) > 1 else "(history object)"
        try:
            data = run_git("cat-file", "blob", oid, cwd=root)
        except subprocess.CalledProcessError:
            continue
        found.append((f"history:{path}", data))
    return found


def self_test() -> None:
    samples = [
        (b"ghp_" + b"A" * 40, "GitHub token"),
        (b"AIza" + b"A" * 36, "Google API key"),
        (b"GOCSPX-" + b"a" * 24, "Google OAuth secret"),
        (b"1//0" + b"a" * 32, "Google refresh token"),
        (b"-----BEGIN " + b"PRIVATE KEY-----", "private key"),
        (b"AKIA" + b"A" * 16, "AWS access key"),
        (b"xoxb-" + b"a" * 30, "Slack token"),
    ]
    for value, expected in samples:
        if expected not in findings(value):
            raise SystemExit(f"Secret scanner self-check failed for {expected}.")
    safe = b"GOOGLE_OAUTH_CLIENT_SECRET GOCSPX-short public.apps.googleusercontent.com"
    if findings(safe):
        raise SystemExit("Secret scanner self-check produced a false positive.")
    print("Secret scanner self-check passed.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--working-tree-only", action="store_true", help="Do not inspect Git history.")
    parser.add_argument("--self-test", action="store_true", help="Check detection and false-positive behavior.")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    self_test()

    root = Path(__file__).resolve().parents[1]
    scanned = working_tree(root)
    if not args.working_tree_only:
        scanned.extend(history(root))
    hits = 0
    for path, data in scanned:
        for kind in findings(data):
            print(f"Potential {kind} in {path}")
            hits += 1
    if hits:
        print(f"Secret scan stopped: {hits} potential credential pattern(s). Values were not printed.", file=sys.stderr)
        return 1
    scope = "working tree" if args.working_tree_only else "working tree and reachable history"
    print(f"Secret scan passed ({scope}; {len(scanned)} files/objects inspected).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
