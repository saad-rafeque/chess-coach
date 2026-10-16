import 'package:flutter/foundation.dart';

import 'chess_engine.dart';

enum EngineStatus { starting, ready, unavailable }

/// Starts the engine once for the whole app and exposes its status.
class EngineHost {
  EngineHost({Future<ChessEngine> Function()? starter}) : _starter = starter ?? ChessEngine.start;

  final Future<ChessEngine> Function() _starter;
  final status = ValueNotifier(EngineStatus.starting);
  Future<ChessEngine?>? _engine;
  Object? error;

  /// The running engine, or null when it couldn't start (callers fall back to simple rules).
  Future<ChessEngine?> get engine => _engine ??= _start();

  Future<ChessEngine?> _start() async {
    try {
      final e = await _starter();
      status.value = EngineStatus.ready;
      return e;
    } catch (e) {
      error = e;
      debugPrint('Engine unavailable: $e');
      status.value = EngineStatus.unavailable;
      return null;
    }
  }

  Future<void> dispose() async => (await _engine)?.dispose();
}
