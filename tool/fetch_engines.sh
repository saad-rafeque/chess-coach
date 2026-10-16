#!/bin/bash
# Downloads the official Stockfish 19 binary for a desktop platform into engines/<platform>/.
# The platform build (CMake) copies it next to the app. Usage: tool/fetch_engines.sh linux|windows
set -euo pipefail

platform="${1:-linux}"
root="$(cd "$(dirname "$0")/.." && pwd)"
base=https://github.com/official-stockfish/Stockfish/releases/download/sf_19

case "$platform" in
  linux)
    asset=stockfish-linux-x86-64-universal.tar.gz
    sha=9defc0d4e55d49c65a6d042f3e571a39fcea499ade6dbe741b53b8c65e03611f
    out=stockfish ;;
  windows)
    asset=stockfish-windows-x86-64-universal.zip
    sha=3c8bf1f9ea66a09350a40df4f632288285ac206d99f33ab5842c408fc30b48a7
    out=stockfish.exe ;;
  *) echo "unknown platform: $platform" >&2; exit 1 ;;
esac

dest="$root/engines/$platform"
if [ -f "$dest/$out" ]; then
  echo "Stockfish already present: $dest/$out"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 5 -o "$tmp/$asset" "$base/$asset"
echo "$sha  $tmp/$asset" | sha256sum -c -

mkdir -p "$tmp/x" "$dest"
case "$asset" in
  *.tar.gz) tar -xzf "$tmp/$asset" -C "$tmp/x" ;;
  *.zip) unzip -q "$tmp/$asset" -d "$tmp/x" ;;
esac
bin="$(find "$tmp/x" -type f -name 'stockfish-*-universal*' | head -1)"
cp "$bin" "$dest/$out"
cp "$tmp/x/stockfish/Copying.txt" "$dest/COPYING-stockfish.txt"
chmod +x "$dest/$out"
echo "Stockfish installed: $dest/$out"
