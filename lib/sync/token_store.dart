import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where the Google refresh token is kept.
abstract interface class TokenStore {
  Future<String?> read();

  /// Saves [token], or removes it when null.
  Future<void> write(String? token);
}

/// Keeps the token in its own file in the app's private folder, never in the shared preferences
/// file or in Documents. On Linux and macOS the file is readable by this user only (mode 600);
/// Windows keeps the folder per user and Android per app (and the app is excluded from backups).
class FileTokenStore implements TokenStore {
  FileTokenStore([Future<Directory> Function()? directory]) : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  static const fileName = 'google-sync-token';

  Future<File> _file() async => File('${(await _directory()).path}${Platform.pathSeparator}$fileName');

  @override
  Future<String?> read() async {
    final f = await _file();
    if (!f.existsSync()) return null;
    final token = (await f.readAsString()).trim();
    return token.isEmpty ? null : token;
  }

  @override
  Future<void> write(String? token) async {
    final f = await _file();
    if (token == null) {
      if (f.existsSync()) await f.delete();
      return;
    }
    await f.parent.create(recursive: true);
    // Restrict the new file before the token goes in, then move it into place in one step.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString('');
    if (Platform.isLinux || Platform.isMacOS) {
      final r = await Process.run('chmod', ['600', tmp.path]);
      if (r.exitCode != 0) throw FileSystemException('Could not protect the sign-in file', tmp.path);
    }
    await tmp.writeAsString(token, flush: true);
    await tmp.rename(f.path);
  }
}

/// Token kept in memory only (tests).
class MemoryTokenStore implements TokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String? value) async => token = value;
}
