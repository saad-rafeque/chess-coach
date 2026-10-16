import 'dart:math' as math;

import '../engine/analysis.dart';

/// Search depth used to pick a move for an opponent of strength [elo].
int depthForElo(int elo) => switch (elo) {
      < 600 => 4,
      < 1000 => 6,
      < 1400 => 8,
      < 1800 => 10,
      < 2200 => 12,
      _ => 16,
    };

/// How many candidate moves the opponent considers.
int candidatesForElo(int elo) => elo < 1000 ? 8 : (elo < 1800 ? 6 : 4);

/// Softmax temperature in centipawns: weaker players accept bigger losses.
double temperatureForElo(int elo) {
  const points = [(400, 220.0), (800, 140.0), (1200, 80.0), (1600, 45.0), (2000, 25.0), (2400, 10.0), (2800, 2.0)];
  if (elo <= points.first.$1) return points.first.$2;
  for (var i = 1; i < points.length; i++) {
    final (e1, t1) = points[i - 1];
    final (e2, t2) = points[i];
    if (elo <= e2) return t1 + (t2 - t1) * (elo - e1) / (e2 - e1);
  }
  return points.last.$2;
}

/// Picks a move like a human of strength [elo]: good moves are likely,
/// weaker ones possible, and the gap shrinks as [elo] rises.
String pickHumanMove(Analysis a, int elo, math.Random rnd) {
  if (a.lines.isEmpty) return a.bestMove!;
  final whiteToMove = a.fen.split(' ')[1] == 'w';
  int forMover(Score s) => whiteToMove ? s.value : -s.value;
  final best = forMover(a.lines.first.score);
  final t = temperatureForElo(elo);
  final weights = [
    for (final l in a.lines) math.exp(-((best - forMover(l.score)).clamp(0, 1500)) / t),
  ];
  final total = weights.reduce((x, y) => x + y);
  var r = rnd.nextDouble() * total;
  for (var i = 0; i < weights.length; i++) {
    r -= weights[i];
    if (r <= 0) return a.lines[i].move;
  }
  return a.lines.last.move;
}

enum MoveQuality { best, good, inaccuracy, mistake, blunder }

extension MoveQualityLabel on MoveQuality {
  String get label => switch (this) {
        MoveQuality.best => 'Best move',
        MoveQuality.good => 'Good move',
        MoveQuality.inaccuracy => 'Inaccuracy',
        MoveQuality.mistake => 'Mistake',
        MoveQuality.blunder => 'Blunder',
      };

  bool get isError => index >= MoveQuality.inaccuracy.index;
}

/// Grades a move by how much it dropped the mover's winning chances
/// (thresholds as on Lichess: 10 / 20 / 30 percentage points).
MoveQuality classifyMove({
  required Score before,
  required Score after,
  required bool moverIsWhite,
  required bool playedBest,
}) {
  double win(Score s) => moverIsWhite ? s.whiteWinPercent : 100 - s.whiteWinPercent;
  final drop = win(before) - win(after);
  if (playedBest || drop <= 2) return MoveQuality.best;
  if (drop < 10) return MoveQuality.good;
  if (drop < 20) return MoveQuality.inaccuracy;
  if (drop < 30) return MoveQuality.mistake;
  return MoveQuality.blunder;
}
