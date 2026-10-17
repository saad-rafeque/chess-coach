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
mkdir -p "$work/AppDir/usr/lib/chess-coach" "$work/AppDir/usr/share/applications" "$work/AppDir/usr/share/icons"
cp -r "$bundle/." "$work/AppDir/usr/lib/chess-coach/"

cat > "$work/AppDir/AppRun" <<'RUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/chess-coach/chess_coach" "$@"
RUN
chmod +x "$work/AppDir/AppRun"

desktop="$root/packaging/linux/com.saadrafeque.chess_coach.desktop"
cp "$desktop" "$work/AppDir/"
cp "$desktop" "$work/AppDir/usr/share/applications/"
cp -r "$root/packaging/linux/icons" "$work/AppDir/usr/share/icons/hicolor"
cp "$root/packaging/linux/icons/256x256/apps/com.saadrafeque.chess_coach.png" "$work/AppDir/com.saadrafeque.chess_coach.png"
ln -sf com.saadrafeque.chess_coach.png "$work/AppDir/.DirIcon"

if [ ! -x "$tool" ]; then
  curl -fsSL --retry 5 -o "$tool" \
    https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
fi
# Only run the exact appimagetool release we checked.
echo "ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0  $tool" | sha256sum -c - \
  || { rm -f "$tool"; exit 1; }
chmod +x "$tool"
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream "$work/AppDir" \
  "$root/build/ChessCoach-$version-x86_64.AppImage"
echo "Built build/ChessCoach-$version-x86_64.AppImage"
