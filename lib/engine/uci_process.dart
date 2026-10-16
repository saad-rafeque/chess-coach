import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:multistockfish/multistockfish.dart';

/// A running UCI engine: send commands, read output lines.
abstract class UciProcess {
  Stream<String> get lines;
  void send(String command);
  Future<void> close();

  /// Starts Stockfish for the current platform.
  static Future<UciProcess> start() async {
    if (Platform.isAndroid || Platform.isIOS) return MobileUciProcess.start();
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      return DesktopUciProcess.start(desktopEnginePath());
    }
    throw UnsupportedError('No chess engine for ${Platform.operatingSystem}');
  }

  /// Engine binary bundled next to the app (see tool/fetch_engines.sh).
  static String desktopEnginePath() {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final name = Platform.isWindows ? 'stockfish.exe' : 'stockfish';
    return '$dir${Platform.pathSeparator}engines${Platform.pathSeparator}$name';
  }
}

/// Stockfish as a child process (Windows, Linux).
class DesktopUciProcess implements UciProcess {
  DesktopUciProcess._(this._process)
      : lines = _process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .asBroadcastStream();

  static Future<DesktopUciProcess> start(String path) async {
    if (!File(path).existsSync()) {
      throw FileSystemException('Stockfish not found', path);
    }
    return DesktopUciProcess._(await Process.start(path, const []));
  }

  final Process _process;

  @override
  final Stream<String> lines;

  @override
  void send(String command) => _process.stdin.writeln(command);

  @override
  Future<void> close() async {
    send('quit');
    await _process.exitCode.timeout(const Duration(seconds: 2), onTimeout: () {
      _process.kill();
      return -1;
    });
  }
}

/// Stockfish 19 (small embedded net) through the multistockfish plugin (Android).
class MobileUciProcess implements UciProcess {
  MobileUciProcess._(this._engine) : lines = _engine.stdout.asBroadcastStream();

  static Future<MobileUciProcess> start() async => MobileUciProcess._(await Stockfish.create());

  final Stockfish _engine;

  @override
  final Stream<String> lines;

  @override
  void send(String command) => _engine.stdin = command;

  @override
  Future<void> close() => _engine.dispose();
}
