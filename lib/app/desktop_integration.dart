import 'dart:io';

import 'package:flutter/foundation.dart';

/// GTK application id; the menu entry and icon are named after it so GNOME and KDE match the window.
const linuxAppId = 'com.saadrafeque.chess_coach';

/// When Chess Coach runs as an AppImage, adds it to the app menu with its icon, as an installer
/// would, and keeps the entry pointing at the current file after an update or a move. The .deb
/// package installs these files itself, so nothing happens there.
Future<void> integrateAppImage({Map<String, String>? environment, String? executable}) async {
  if (!Platform.isLinux && environment == null) return;
  final env = environment ?? Platform.environment;
  final appImage = env['APPIMAGE'];
  final home = env['HOME'];
  if (appImage == null || appImage.isEmpty || home == null) return;
  try {
    final dataHome = (env['XDG_DATA_HOME'] ?? '').isNotEmpty ? env['XDG_DATA_HOME']! : '$home/.local/share';
    final bundle = File(executable ?? Platform.resolvedExecutable).parent.path;
    final icon = File('$bundle/data/app_icon.png');
    final iconTarget = File('$dataHome/icons/hicolor/512x512/apps/$linuxAppId.png');
    var changed = false;
    if (icon.existsSync() &&
        (!iconTarget.existsSync() || iconTarget.lengthSync() != icon.lengthSync())) {
      await iconTarget.parent.create(recursive: true);
      await icon.copy(iconTarget.path);
      changed = true;
    }
    final desktop = File('$dataHome/applications/$linuxAppId.desktop');
    final entry = desktopEntry(appImage);
    if (!desktop.existsSync() || desktop.readAsStringSync() != entry) {
      await desktop.parent.create(recursive: true);
      await desktop.writeAsString(entry);
      changed = true;
    }
    if (changed) {
      // Best effort: menus also pick the changes up on their own after a while.
      await Process.run('update-desktop-database', ['$dataHome/applications']).catchError((Object _) => ProcessResult(0, 0, '', ''));
      await Process.run('gtk-update-icon-cache', ['-f', '-t', '$dataHome/icons/hicolor'])
          .catchError((Object _) => ProcessResult(0, 0, '', ''));
    }
  } catch (e) {
    debugPrint('App menu entry not updated: $e');
  }
}

/// The menu entry for the AppImage at [appImage].
String desktopEntry(String appImage) => '''[Desktop Entry]
Type=Application
Name=Chess Coach
Comment=Your personal chess coach
Exec=${_quote(appImage)}
Icon=$linuxAppId
Categories=Game;BoardGame;Education;
Keywords=chess;coach;training;puzzles;
Terminal=false
StartupWMClass=$linuxAppId
''';

/// Quotes a path for the Exec key of a desktop entry (quoting rules first, then string escapes).
String _quote(String path) {
  final escaped = path.replaceAllMapped(RegExp(r'["`$\\%]'), (m) => switch (m[0]!) {
        '\\' => r'\\\\',
        '%' => '%%',
        final c => '\\\\$c',
      });
  return '"$escaped"';
}
