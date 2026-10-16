#!/bin/bash
# Packs the Linux release bundle into an AppImage. Run after `flutter build linux --release`.
# Usage: packaging/linux/build_appimage.sh <version>
set -euo pipefail

version="${1:?version required}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
bundle="$root/build/linux/x64/release/bundle"
work="$root/build/appimage"
tool="$work/appimagetool"

rm -rf "$work/AppDir"
mkdir -p "$work/AppDir/usr/lib/chess-coach" "$work/AppDir/usr/share/applications" \
  "$work/AppDir/usr/share/icons/hicolor/256x256/apps"
cp -r "$bundle/." "$work/AppDir/usr/lib/chess-coach/"

cat > "$work/AppDir/AppRun" <<'RUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/chess-coach/chess_coach" "$@"
RUN
chmod +x "$work/AppDir/AppRun"

cp "$root/packaging/linux/chess-coach.desktop" "$work/AppDir/chess-coach.desktop"
cp "$root/packaging/linux/chess-coach.desktop" "$work/AppDir/usr/share/applications/"
cp "$root/assets/icon/icon.png" "$work/AppDir/chess-coach.png"
cp "$root/assets/icon/icon.png" "$work/AppDir/usr/share/icons/hicolor/256x256/apps/chess-coach.png"
ln -sf chess-coach.png "$work/AppDir/.DirIcon"

if [ ! -x "$tool" ]; then
  curl -fsSL --retry 5 -o "$tool" \
    https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
  chmod +x "$tool"
fi
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream "$work/AppDir" \
  "$root/build/ChessCoach-$version-x86_64.AppImage"
echo "Built build/ChessCoach-$version-x86_64.AppImage"
