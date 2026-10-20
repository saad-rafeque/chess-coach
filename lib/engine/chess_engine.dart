import 'dart:async';
import 'dart:io';

import 'analysis.dart';
import 'uci_process.dart';

/// High-level Stockfish wrapper. Searches run one at a time in the order requested.
class ChessEngine {
  ChessEngine(this._process);

  final UciProcess _process;
  Future<void> _queue = Future.value();
  bool _closed = false;

  static Future<ChessEngine> start({UciProcess? process, Duration startTimeout = const Duration(seconds: 90)}) async {
    final engine = ChessEngine(process ?? await UciProcess.start());
    try {
      await engine._handshake(startTimeout);
    } catch (_) {
      // Don't leave a half-started engine running in the background.
      await engine.dispose().catchError((Object _) {});
      rethrow;
    }
    return engine;
  }

  /// The first start can be slow (a cold disk, or the AppImage unpacking the 100 MB engine), so the
  /// handshake gets [timeout]; later commands answer within milliseconds.
  Future<void> _handshake(Duration timeout) async {
    final ok = _waitFor('uciok', timeout);
    _process.send('uci');
    await ok;
    final threads = (Platform.numberOfProcessors - 1).clamp(1, 4);
    _process.send('setoption name Threads value $threads');
    _process.send('setoption name Hash value 64');
    await _ready(timeout);
  }

  Future<void> _ready([Duration timeout = const Duration(seconds: 15)]) async {
    final ok = _waitFor('readyok', timeout);
    _process.send('isready');
    await ok;
  }

  Future<String> _waitFor(String prefix, Duration timeout) =>
      _process.lines.firstWhere((l) => l.startsWith(prefix)).timeout(timeout);

  /// Analyses [fen]. Stops at [depth] or after [movetime], whichever is given.
  Future<Analysis> analyse(
    String fen, {
    int depth = 14,
    Duration? movetime,
    int multiPv = 1,
    Duration searchTimeout = const Duration(seconds: 60),
  }) {
    final result = _queue.then(
      (_) => _search(
        fen,
        depth: depth,
        movetime: movetime,
        multiPv: multiPv,
        searchTimeout: searchTimeout,
      ),
    );
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Analysis> _search(
    String fen, {
    required int depth,
    Duration? movetime,
    required int multiPv,
    required Duration searchTimeout,
  }) async {
    if (_closed) throw StateError('Engine is closed');
    // One UCI command per line: a line break would let the text run engine commands.
    if (fen.contains('\n') || fen.contains('\r')) throw ArgumentError.value(fen, 'fen', 'must be one line');
    final tokens = fen.trim().split(RegExp(r'\s+'));
    final whiteToMove = tokens.length > 1 ? tokens[1] != 'b' : true;
    final best = <int, EngineLine>{};
    final done = Completer<String?>();
    final sub = _process.lines.listen((line) {
      if (line.startsWith('bestmove')) {
        final parts = line.split(' ');
        final move = parts.length > 1 && parts[1] != '(none)' ? parts[1] : null;
        if (!done.isCompleted) done.complete(move);
        return;
      }
      final info = parseInfo(line, whiteToMove: whiteToMove);
      if (info != null) best[info.multipv] = info;
    });
    try {
      _process.send('setoption name MultiPV value $multiPv');
      await _ready();
      _process.send('position fen $fen');
      _process.send(movetime != null ? 'go movetime ${movetime.inMilliseconds}' : 'go depth $depth');
      final move = await done.future.timeout(searchTimeout);
      final lines = best.values.toList()..sort((a, b) => a.multipv.compareTo(b.multipv));
      return Analysis(fen: fen, lines: lines, bestMove: move);
    } catch (_) {
      try {
        _process.send('stop');
      } catch (_) {}
      rethrow;
    } finally {
      await sub.cancel();
    }
  }

  Future<void> dispose() async {
    _closed = true;
    await _process.close();
  }
}
