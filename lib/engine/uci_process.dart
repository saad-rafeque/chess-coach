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
    final installed = '$dir${Platform.pathSeparator}engines${Platform.pathSeparator}$name';
    if (File(installed).existsSync()) return installed;
    final platformDir = Platform.isWindows ? 'windows' : (Platform.isMacOS ? 'macos' : 'linux');
    final devPath = '${Directory.current.path}${Platform.pathSeparator}engines${Platform.pathSeparator}$platformDir${Platform.pathSeparator}$name';
    if (File(devPath).existsSync()) return devPath;
    return installed;
  }
}

/// Stockfish as a child process (Windows, Linux).
class DesktopUciProcess implements UciProcess {
  DesktopUciProcess._(this._process)
      : lines = _process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .asBroadcastStream() {
    _process.stderr.drain<void>().catchError((Object _) {});
  }

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
  void send(String command) {
    try {
      _process.stdin.writeln(command);
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    try {
      send('quit');
      await _process.stdin.flush().catchError((Object _) {});
    } catch (_) {}
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
