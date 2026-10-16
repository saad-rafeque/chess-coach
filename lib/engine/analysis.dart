import 'dart:math' as math;

/// Engine score from White's point of view.
class Score implements Comparable<Score> {
  const Score.cp(int this.cp) : mate = null;
  const Score.mate(int this.mate) : cp = null;

  /// Centipawns, positive = White is better.
  final int? cp;

  /// Moves to mate, positive = White mates.
  final int? mate;

  Score get flipped => cp != null ? Score.cp(-cp!) : Score.mate(-mate!);

  /// Centipawn-like value; mates map to ±(10000 - distance).
  int get value => cp ?? (mate! > 0 ? 10000 - mate! : -10000 - mate!);

  /// White's winning chances, 0..100 (Lichess formula).
  double get whiteWinPercent {
    if (mate != null) return mate! > 0 ? 100 : 0;
    final c = cp!.clamp(-1000, 1000);
    return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * c)) - 1);
  }

  /// Short label such as +1.2 or M3.
  String get label {
    if (mate != null) return mate! > 0 ? 'M${mate!}' : '-M${-mate!}';
    final pawns = cp! / 100;
    return '${pawns >= 0 ? '+' : ''}${pawns.toStringAsFixed(1)}';
  }

  @override
  int compareTo(Score other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is Score && other.cp == cp && other.mate == mate;

  @override
  int get hashCode => Object.hash(cp, mate);

  @override
  String toString() => label;
}

/// One principal variation from a `go` search.
class EngineLine {
  const EngineLine({required this.multipv, required this.depth, required this.score, required this.pv});

  final int multipv;
  final int depth;

  /// From White's point of view.
  final Score score;

  /// Moves in UCI notation, first = the suggested move.
  final List<String> pv;

  String get move => pv.first;
}

class Analysis {
  const Analysis({required this.fen, required this.lines, required this.bestMove});

  final String fen;

  /// Best line first.
  final List<EngineLine> lines;
  final String? bestMove;

  Score? get score => lines.isEmpty ? null : lines.first.score;
  int get depth => lines.isEmpty ? 0 : lines.first.depth;
}

/// Parses a UCI `info` line. Returns null for lines without a score and PV.
/// [whiteToMove] converts the side-to-move score into White's point of view.
EngineLine? parseInfo(String line, {required bool whiteToMove}) {
  if (!line.startsWith('info ')) return null;
  final t = line.split(' ');
  int? depth, cp, mate;
  var multipv = 1;
  List<String>? pv;
  for (var i = 1; i < t.length; i++) {
    switch (t[i]) {
      case 'depth':
        depth = int.tryParse(t[++i]);
      case 'multipv':
        multipv = int.tryParse(t[++i]) ?? 1;
      case 'score':
        final kind = t[++i];
        final v = int.tryParse(t[++i]);
        if (kind == 'cp') cp = v;
        if (kind == 'mate') mate = v;
      case 'pv':
        pv = t.sublist(i + 1);
        i = t.length;
    }
  }
  if (depth == null || pv == null || pv.isEmpty || (cp == null && mate == null)) return null;
  var score = cp != null ? Score.cp(cp) : Score.mate(mate!);
  if (!whiteToMove) score = score.flipped;
  return EngineLine(multipv: multipv, depth: depth, score: score, pv: pv);
}
