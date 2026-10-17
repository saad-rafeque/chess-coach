import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

import '../coach/coach_player.dart';
import '../coach/explain.dart';
import '../data/event_store.dart';
import '../data/game_record.dart';
import '../engine/analysis.dart';
import '../engine/chess_engine.dart';

/// Engine results for every position of a game: index i = position after i moves.
class GameAnalysis {
  const GameAnalysis({required this.scores, required this.best});

  factory GameAnalysis.fromData(Map<String, dynamic> d) => GameAnalysis(
        scores: [
          for (final s in d['scores'] as List<dynamic>)
            (s as Map)['mate'] != null ? Score.mate(s['mate'] as int) : Score.cp(s['cp'] as int),
        ],
        best: (d['best'] as List<dynamic>).cast<String?>(),
      );

  /// White's point of view.
  final List<Score> scores;
  final List<String?> best;

  static const eventType = 'review';

  Map<String, dynamic> toData(String gameId) => {
        'game': gameId,
        'scores': [for (final s in scores) s.mate != null ? {'mate': s.mate} : {'cp': s.cp}],
        'best': best,
      };
}

/// Final positions get a fixed score; the engine has nothing to search.
Score? _terminalScore(Position p) {
  if (p.isCheckmate) return Score.cp(p.turn == Side.white ? -10000 : 10000);
  if (p.isGameOver) return const Score.cp(0);
  return null;
}

/// Analyses every position of [game]. [onProgress] gets (done, total).
Future<GameAnalysis> analyseGame(ChessEngine engine, GameRecord game,
    {int depth = 12, void Function(int done, int total)? onProgress}) async {
  final positions = game.positions();
  final scores = <Score>[];
  final best = <String?>[];
  for (var i = 0; i < positions.length; i++) {
    final p = positions[i];
    final terminal = _terminalScore(p);
    if (terminal != null) {
      scores.add(terminal);
      best.add(null);
    } else {
      final a = await engine.analyse(p.fen, depth: depth);
      scores.add(a.score ?? (scores.isEmpty ? const Score.cp(0) : scores.last));
      best.add(a.bestMove);
    }
    onProgress?.call(i + 1, positions.length);
  }
  return GameAnalysis(scores: scores, best: best);
}

class ReviewedMove {
  const ReviewedMove({
    required this.ply,
    required this.san,
    required this.uci,
    required this.mover,
    required this.before,
    required this.after,
    required this.bestUci,
    required this.bestSan,
    required this.quality,
    required this.accuracy,
    required this.winDrop,
    required this.explanation,
  });

  final int ply;
  final String san;
  final String uci;
  final Side mover;
  final Score before;
  final Score after;
  final String? bestUci;
  final String? bestSan;
  final MoveQuality quality;

  /// 0..100, Lichess-style per-move accuracy.
  final double accuracy;

  /// How much the mover's winning chances dropped, in percentage points.
  final double winDrop;

  /// Why it was an error (null for good moves).
  final String? explanation;
}

class GameReview {
  const GameReview(this.game, this.moves);

  final GameRecord game;
  final List<ReviewedMove> moves;

  Iterable<ReviewedMove> movesOf(Side side) => moves.where((m) => m.mover == side);

  double accuracy(Side side) {
    final list = movesOf(side).map((m) => m.accuracy).toList();
    return list.isEmpty ? 100 : list.reduce((a, b) => a + b) / list.length;
  }

  int count(Side side, MoveQuality q) => movesOf(side).where((m) => m.quality == q).length;

  /// The player's biggest errors, worst first.
  List<ReviewedMove> keyMoments({int max = 3}) {
    final errors = movesOf(game.playerSide).where((m) => m.quality.isError).toList()
      ..sort((a, b) => b.winDrop.compareTo(a.winDrop));
    return errors.take(max).toList()..sort((a, b) => a.ply.compareTo(b.ply));
  }
}

double moveAccuracy(double winDrop) =>
    (103.1668100711649 * math.exp(-0.04354415386753951 * math.max(0, winDrop)) - 3.166924740191411)
        .clamp(0, 100)
        .toDouble();

GameReview buildReview(GameRecord game, GameAnalysis analysis) {
  final positions = game.positions();
  final sans = game.sans();
  final reviewed = <ReviewedMove>[];
  // An analysis from a damaged copy may be shorter than the game: review what it covers.
  final n = math.min(game.moves.length, math.min(analysis.scores.length, analysis.best.length) - 1);
  for (var i = 0; i < n; i++) {
    final before = positions[i];
    final after = positions[i + 1];
    final mover = before.turn;
    final sBefore = analysis.scores[i];
    final sAfter = analysis.scores[i + 1];
    double win(Score s) => mover == Side.white ? s.whiteWinPercent : 100 - s.whiteWinPercent;
    final drop = win(sBefore) - win(sAfter);
    final bestUci = analysis.best[i];
    final bestMove = bestUci == null ? null : Move.parse(bestUci);
    final playedBest = bestMove != null && before.isLegal(bestMove) && before.play(bestMove).fen == after.fen;
    final quality = classifyMove(before: sBefore, after: sAfter, moverIsWhite: mover == Side.white, playedBest: playedBest);
    String? why;
    if (quality.isError && bestUci != null) {
      Analysis wrap(Position p, Score s, String? m) =>
          Analysis(fen: p.fen, bestMove: m, lines: [if (m != null) EngineLine(multipv: 1, depth: 0, score: s, pv: [m])]);
      why = explainError(
        quality: quality,
        before: before,
        beforeAnalysis: wrap(before, sBefore, bestUci),
        after: after,
        afterAnalysis: wrap(after, sAfter, analysis.best[i + 1]),
      );
    }
    reviewed.add(ReviewedMove(
      ply: i,
      san: sans[i],
      uci: game.moves[i],
      mover: mover,
      before: sBefore,
      after: sAfter,
      bestUci: bestUci,
      bestSan: bestUci == null ? null : sanOf(before, bestUci),
      quality: quality,
      accuracy: playedBest ? 100 : moveAccuracy(drop),
      winDrop: drop,
      explanation: why,
    ));
  }
  return GameReview(game, reviewed);
}

final _reviewCache = <String, GameReview>{};

/// [buildReview] for a stored analysis event, computed once per event (games and
/// analyses never change once stored).
GameReview cachedReview(GameRecord game, AppEvent analysis) {
  final hit = _reviewCache[analysis.id];
  if (hit != null) return hit;
  if (_reviewCache.length > 400) _reviewCache.remove(_reviewCache.keys.first);
  return _reviewCache[analysis.id] = buildReview(game, GameAnalysis.fromData(analysis.data));
}
