import 'package:flutter/widgets.dart';

import 'chess_engine.dart';

enum EngineStatus { starting, ready, unavailable }

/// Starts the engine once for the whole app and exposes its status.
class EngineHost {
  EngineHost({Future<ChessEngine> Function()? starter, this.retryAfter = const Duration(seconds: 20)})
      : _starter = starter ?? ChessEngine.start;

  final Future<ChessEngine> Function() _starter;
  final status = ValueNotifier(EngineStatus.starting);
  Future<ChessEngine?>? _engine;
  Object? error;

  /// After a failed start, the next request tries again once this much time has passed.
  final Duration retryAfter;
  DateTime? _failedAt;

  /// The running engine, or null when it couldn't start (callers fall back to simple rules).
  Future<ChessEngine?> get engine {
    final failed = _failedAt;
    if (failed != null && DateTime.now().difference(failed) >= retryAfter) {
      _failedAt = null;
      _engine = null;
    }
    return _engine ??= _start();
  }

  Future<ChessEngine?> _start() async {
    status.value = EngineStatus.starting;
    try {
      final e = await _starter();
      status.value = EngineStatus.ready;
      return e;
    } catch (e) {
      error = e;
      _failedAt = DateTime.now();
      debugPrint('Engine unavailable: $e');
      status.value = EngineStatus.unavailable;
      return null;
    }
  }

  Future<void> dispose() async => (await _engine)?.dispose();
}

/// Makes the app's [EngineHost] available to widgets.
class EngineScope extends InheritedWidget {
  const EngineScope({super.key, required this.host, required super.child});

  final EngineHost host;

  static EngineHost of(BuildContext context) => context.getInheritedWidgetOfExactType<EngineScope>()!.host;

  @override
  bool updateShouldNotify(EngineScope oldWidget) => host != oldWidget.host;
}
