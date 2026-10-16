import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/event_store.dart';
import '../train/glicko2.dart';

/// Friendly names for Lichess puzzle themes shown in the app.
const themeNames = {
  'mateIn1': 'Mate in 1',
  'mateIn2': 'Mate in 2',
  'mateIn3': 'Mate in 3',
  'fork': 'Fork',
  'pin': 'Pin',
  'skewer': 'Skewer',
  'hangingPiece': 'Hanging piece',
  'discoveredAttack': 'Discovered attack',
  'backRankMate': 'Back-rank mate',
  'trappedPiece': 'Trapped piece',
  'sacrifice': 'Sacrifice',
  'deflection': 'Deflection',
  'attraction': 'Attraction',
  'promotion': 'Promotion',
  'endgame': 'Endgame',
  'opening': 'Opening',
  'middlegame': 'Middlegame',
  'defensiveMove': 'Defence',
  'yourMistakes': 'Your mistakes',
};

/// A puzzle: Lichess puzzles start with the opponent's move ([setup] = true),
/// then the solution alternates between the player and the opponent.
class PuzzleItem {
  const PuzzleItem({
    required this.id,
    required this.fen,
    required this.moves,
    required this.rating,
    required this.themes,
    this.setup = true,
  });

  /// Parses a `id<TAB>fen<TAB>moves<TAB>rating<TAB>themes` line.
  static PuzzleItem? parse(String line) {
    final t = line.split('\t');
    if (t.length < 5) return null;
    return PuzzleItem(
      id: t[0],
      fen: t[1],
      moves: t[2].split(' '),
      rating: int.tryParse(t[3]) ?? 1500,
      themes: t[4].isEmpty ? const [] : t[4].split(' '),
    );
  }

  final String id;
  final String fen;
  final List<String> moves;
  final int rating;
  final List<String> themes;
  final bool setup;

  /// Themes the app has names for, most specific first.
  List<String> get namedThemes => [for (final t in themes) if (themeNames.containsKey(t)) themeNames[t]!];
}

/// The bundled Lichess puzzle set (CC0), indexed by theme.
class PuzzleBank {
  PuzzleBank(this.puzzles) {
    for (final p in puzzles) {
      for (final t in p.themes) {
        (byTheme[t] ??= []).add(p);
      }
    }
  }

  final List<PuzzleItem> puzzles;
  final byTheme = <String, List<PuzzleItem>>{};

  static Future<PuzzleBank>? _shared;

  /// Loads `assets/puzzles/puzzles.tsv.gz` once, parsing off the UI thread.
  static Future<PuzzleBank> shared() => _shared ??= () async {
        final data = await rootBundle.load('assets/puzzles/puzzles.tsv.gz');
        final bytes = data.buffer.asUint8List();
        return Isolate.run(() => fromGzip(bytes));
      }();

  static PuzzleBank fromGzip(List<int> bytes) {
    final text = utf8.decode(GZipCodec().decode(bytes));
    return PuzzleBank([
      for (final line in text.split('\n'))
        if (line.isNotEmpty) ?PuzzleItem.parse(line),
    ]);
  }

  /// A puzzle near [rating] (slightly harder on average), optionally of [theme],
  /// skipping ids in [exclude].
  PuzzleItem? next({required double rating, String? theme, Set<String> exclude = const {}, math.Random? random}) {
    final rnd = random ?? math.Random();
    final pool = theme == null ? puzzles : (byTheme[theme] ?? const []);
    if (pool.isEmpty) return null;
    for (final window in [100, 200, 400, 800, 3000]) {
      final lo = rating - window * 0.6, hi = rating + window;
      final candidates = [
        for (final p in pool)
          if (p.rating >= lo && p.rating <= hi && !exclude.contains(p.id)) p,
      ];
      if (candidates.isNotEmpty) return candidates[rnd.nextInt(candidates.length)];
    }
    return pool[rnd.nextInt(pool.length)];
  }
}

// ------------------------------------------------------------- your record --

const puzzleEventType = 'puzzle';

/// Puzzle rating and counters derived from the stored puzzle attempts.
class PuzzleStats {
  const PuzzleStats({required this.rating, required this.solved, required this.attempted, required this.streakDays, required this.seen});

  factory PuzzleStats.fromEvents(Iterable<AppEvent> events, {DateTime? today}) {
    var r = Rating.beginner;
    var solved = 0, attempted = 0;
    final days = <DateTime>{};
    final seen = <String>{};
    for (final e in events.where((e) => e.type == puzzleEventType)) {
      final ok = e.data['solved'] == true;
      final pr = (e.data['puzzleRating'] as num?)?.toDouble();
      if (e.data['rated'] != false && pr != null) r = glicko2Update(r, pr, 80, ok ? 1 : 0);
      attempted++;
      if (ok) {
        solved++;
        final t = e.time.toLocal();
        days.add(DateTime(t.year, t.month, t.day));
      }
      seen.add(e.data['id'] as String);
    }
    final now = today ?? DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    if (!days.contains(day)) day = day.subtract(const Duration(days: 1));
    var streak = 0;
    while (days.contains(day)) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return PuzzleStats(rating: r, solved: solved, attempted: attempted, streakDays: streak, seen: seen);
  }

  final Rating rating;
  final int solved;
  final int attempted;
  final int streakDays;

  /// Ids of puzzles already tried.
  final Set<String> seen;
}

// ------------------------------------------------------------------ session --

enum PuzzleState { opponentMoving, playerToMove, wrongMove, solved, showingSolution }

/// Plays one puzzle: animates the opponent's moves and checks the player's.
class PuzzleSession extends ChangeNotifier {
  PuzzleSession(this.puzzle, {this.onResult, this.moveDelay = const Duration(milliseconds: 550)}) {
    position = Chess.fromSetup(Setup.parseFen(puzzle.fen));
    playerSide = puzzle.setup ? position.turn.opposite : position.turn;
  }

  final PuzzleItem puzzle;

  /// Called once with the first-attempt outcome.
  final void Function(PuzzleItem puzzle, bool solved)? onResult;
  final Duration moveDelay;

  late Position position;
  late final Side playerSide;
  NormalMove? lastMove;
  int _next = 0;
  PuzzleState state = PuzzleState.opponentMoving;
  bool _reported = false;
  bool _disposed = false;
  Square? hintSquare;

  bool get finished => state == PuzzleState.solved || state == PuzzleState.showingSolution;
  NormalMove get _expected => NormalMove.fromUci(puzzle.moves[_next]);

  Future<void> start() async {
    if (puzzle.setup) {
      await Future<void>.delayed(moveDelay);
      _play(_expected);
    }
    state = PuzzleState.playerToMove;
    _notify();
  }

  /// Returns true if [move] is correct.
  Future<bool> playerMove(NormalMove move) async {
    if (state != PuzzleState.playerToMove && state != PuzzleState.wrongMove) return false;
    if (!position.isLegal(move)) return false;
    final expected = _expected;
    final after = position.play(move);
    final isLast = _next == puzzle.moves.length - 1;
    final correct = after.fen == position.play(expected).fen || (isLast && after.isCheckmate);
    if (!correct) {
      _report(false);
      state = PuzzleState.wrongMove;
      _notify();
      return false;
    }
    hintSquare = null;
    _play(move);
    if (_next >= puzzle.moves.length) {
      _report(true);
      state = PuzzleState.solved;
      _notify();
      return true;
    }
    state = PuzzleState.opponentMoving;
    _notify();
    await Future<void>.delayed(moveDelay);
    if (_disposed) return true;
    _play(_expected);
    state = PuzzleState.playerToMove;
    _notify();
    return true;
  }

  void hint() {
    if (finished || state == PuzzleState.opponentMoving) return;
    hintSquare = _expected.from;
    _notify();
  }

  /// Plays out the rest of the solution; counts as not solved.
  Future<void> showSolution() async {
    if (finished) return;
    _report(false);
    state = PuzzleState.showingSolution;
    hintSquare = null;
    _notify();
    while (_next < puzzle.moves.length && !_disposed) {
      await Future<void>.delayed(moveDelay);
      if (_disposed) return;
      _play(_expected);
      _notify();
    }
  }

  void _play(NormalMove m) {
    position = position.play(m);
    lastMove = m;
    _next++;
  }

  void _report(bool solved) {
    if (_reported) return;
    _reported = true;
    onResult?.call(puzzle, solved);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
