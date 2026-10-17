import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Where the Google refresh token is kept.
abstract interface class TokenStore {
  Future<String?> read();

  /// Saves [token], or removes it when null.
  Future<void> write(String? token);
}

/// Keeps the token in the platform keychain: Windows DPAPI, Linux libsecret
/// (the desktop secret service), macOS Keychain, Android Keystore. Where no
/// keychain service exists (tests, Linux desktops without one) it falls back
/// to [FileTokenStore], so sign-in keeps working. A token stored by an older
/// version in the plain file is moved into the keychain on the next read.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage, Future<Directory> Function()? directory})
      : _storage = storage ?? const FlutterSecureStorage(),
        _file = FileTokenStore(directory);

  static const _key = 'google-sync-token';

  final FlutterSecureStorage _storage;
  final FileTokenStore _file;

  @override
  Future<String?> read() async {
    try {
      final token = await _storage.read(key: _key);
      if (token != null && token.isNotEmpty) return token;
      final legacy = await _file.read();
      if (legacy == null) return null;
      await write(legacy); // move it out of the plain file
      return legacy;
    } on PlatformException {
      return _file.read();
    } on MissingPluginException {
      return _file.read();
    }
  }

  @override
  Future<void> write(String? token) async {
    try {
      if (token == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: token);
      }
      await _file.write(null); // no plain copy next to the keychain one
    } on PlatformException {
      await _file.write(token);
    } on MissingPluginException {
      await _file.write(token);
    }
  }
}

/// Keeps the token in its own file in the app's private folder, never in the shared preferences
/// file or in Documents. On Linux and macOS the file is readable by this user only (mode 600);
/// Windows keeps the folder per user and Android per app (and the app is excluded from backups).
/// Prefer [SecureTokenStore], which uses the platform keychain and falls back to this file.
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
