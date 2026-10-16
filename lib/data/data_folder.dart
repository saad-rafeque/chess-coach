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
    return private;
  }
  final dir = Directory('${docs.path}${Platform.pathSeparator}Chess Coach');
  try {
    await dir.create(recursive: true);
    await migrateLegacyData(private, dir);
    final readme = File('${dir.path}${Platform.pathSeparator}README.txt');
    if (!readme.existsSync()) await readme.writeAsString(_readme);
    return dir;
  } catch (_) {
    return private;
  }
}

/// Moves data from the old hidden folder [from] into [to], never overwriting anything in [to].
Future<void> migrateLegacyData(Directory from, Directory to) async {
  final sep = Platform.pathSeparator;
  final oldEvents = File('${from.path}${sep}events.jsonl');
  final newEvents = File('${to.path}${sep}events.jsonl');
  if (oldEvents.existsSync() && !newEvents.existsSync()) {
    await oldEvents.copy(newEvents.path);
    await oldEvents.rename('${oldEvents.path}.moved-to-documents');
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
}
