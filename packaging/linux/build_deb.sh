#!/bin/bash
# Packs the Linux release bundle into a .deb. Run after `flutter build linux --release`.
# Usage: packaging/linux/build_deb.sh <version>
# Installs to /opt/chess-coach, adds a `chess-coach` command and a menu entry.
set -euo pipefail

version="${1:?version required}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
bundle="$root/build/linux/x64/release/bundle"
work="$root/build/deb/chess-coach_${version}_amd64"
out="$root/build/ChessCoach-$version-amd64.deb"

rm -rf "$work"
mkdir -p "$work/DEBIAN" "$work/opt/chess-coach" "$work/usr/bin" "$work/usr/share/applications" \
  "$work/usr/share/icons"
cp -r "$bundle/." "$work/opt/chess-coach/"
ln -s /opt/chess-coach/chess_coach "$work/usr/bin/chess-coach"

# Desktop file and icons are named after the GTK application id, so the dock and app grid find them on
# Wayland.
cp "$root/packaging/linux/com.saadrafeque.chess_coach.desktop" "$work/usr/share/applications/"
cp -r "$root/packaging/linux/icons" "$work/usr/share/icons/hicolor"

size=$(du -sk "$work/opt" "$work/usr" | awk '{s += $1} END {print s}')
cat > "$work/DEBIAN/control" <<CONTROL
Package: chess-coach
Version: $version
Architecture: amd64
Maintainer: Saad Rafique <126379716+saad-rafeque@users.noreply.github.com>
Installed-Size: $size
Depends: libgtk-3-0 | libgtk-3-0t64, libc6 (>= 2.31)
Section: games
Priority: optional
Homepage: https://github.com/saad-rafeque/chess-coach
Description: Personal offline chess coach
 Plays you at your level with human-like Maia networks and Stockfish 19,
 explains your mistakes, and plans lessons, puzzles and reviews for you.
CONTROL

# Data lives in Documents/Chess Coach and is never removed by uninstalling.
cat > "$work/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q /usr/share/icons/hicolor || true
POSTINST

# Standard permissions: nothing group- or world-writable.
chmod -R u=rwX,go=rX "$work"
chmod 755 "$work/DEBIAN/postinst"
dpkg-deb --root-owner-group --build "$work" "$out"
echo "Built ${out#"$root"/}"
