import 'dart:io';

import 'package:path_provider/path_provider.dart';

const _readme = '''This folder holds your Chess Coach data.

events.jsonl  Everything you did: games, reviews, puzzles, lessons, review cards. Keep it safe; it is also
              copied to your Google Drive when sync is connected.
models/       The optional language model for friendly explanations (you can delete it in Settings).

Please don't edit these files by hand.
''';

/// Where the app keeps its data: `Documents/Chess Coach` on Windows and Linux, so it is easy to
/// find and back up; the app's private folder on phones. Data from older versions, kept in the
/// hidden app folder, is copied here the first time.
Future<Directory> dataFolder() async {
  final private = await getApplicationSupportDirectory();
  if (Platform.isAndroid || Platform.isIOS) return private;
  final Directory docs;
  try {
    docs = await getApplicationDocumentsDirectory();
  } catch (_) {
    await secureDataTree(private);
    return private;
  }
  final dir = Directory('${docs.path}${Platform.pathSeparator}Chess Coach');
  try {
    await dir.create(recursive: true);
    await secureDataTree(private);
    await secureDataTree(dir);
    await migrateLegacyData(private, dir);
    final readme = File('${dir.path}${Platform.pathSeparator}README.txt');
    if (!readme.existsSync()) await readme.writeAsString(_readme);
    await secureDataTree(dir);
    return dir;
  } catch (_) {
    await secureDataTree(private);
    return private;
  }
}

/// Restricts the app's own data tree on Unix. The Android and iOS app sandboxes
/// and Windows per-user profile ACLs already provide the platform boundary.
Future<void> secureDataTree(Directory root) async {
  final rootType = await FileSystemEntity.type(root.path, followLinks: false);
  if (rootType == FileSystemEntityType.link ||
      rootType == FileSystemEntityType.file) {
    throw FileSystemException(
      'Refusing to use a link or file as the app data directory.',
      root.path,
    );
  }
  await root.create(recursive: true);
  if (!_usesPosixPermissions) return;

  await _chmod(root.path, '700');
  await for (final entry in root.list(recursive: true, followLinks: false)) {
    final type = await FileSystemEntity.type(entry.path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await _chmod(entry.path, '700');
    } else if (type == FileSystemEntityType.file) {
      await _chmod(entry.path, '600');
    }
  }
}

/// Creates a private event file before it can contain user history, and fixes
/// permissions on an existing file before it is read or appended to.
Future<void> secureDataFile(File file) async {
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    throw FileSystemException(
      'Refusing to use a symbolic link for app data.',
      file.path,
    );
  }
  if (type == FileSystemEntityType.notFound) await file.create();
  if (_usesPosixPermissions) await _chmod(file.path, '600');
}

bool get _usesPosixPermissions => Platform.isLinux || Platform.isMacOS;

Future<void> _chmod(String path, String mode) async {
  final result = await Process.run('chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'Could not restrict Chess Coach data permissions.',
      path,
    );
  }
}

/// Moves data from the old hidden folder [from] into [to], never overwriting anything in [to].
Future<void> migrateLegacyData(Directory from, Directory to) async {
  if (await from.exists()) await secureDataTree(from);
  await secureDataTree(to);
  final sep = Platform.pathSeparator;
  final oldEvents = File('${from.path}${sep}events.jsonl');
  final newEvents = File('${to.path}${sep}events.jsonl');
  if (oldEvents.existsSync() && !newEvents.existsSync()) {
    await oldEvents.copy(newEvents.path);
    await secureDataFile(newEvents);
    await oldEvents.rename('${oldEvents.path}.moved-to-documents');
    await secureDataFile(File('${oldEvents.path}.moved-to-documents'));
  }
  final oldModels = Directory('${from.path}${sep}models');
  final newModels = Directory('${to.path}${sep}models');
  if (oldModels.existsSync() && !newModels.existsSync()) {
    try {
      await oldModels.rename(newModels.path);
    } on FileSystemException {
      // Another drive: leave the models where they are; they can be downloaded again.
    }
  }
  await secureDataTree(to);
}
