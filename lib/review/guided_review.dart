import 'package:dartchess/dartchess.dart';

import '../coach/coach_player.dart';
import '../coach/explain.dart';
import '../data/curriculum.dart';
import '../engine/analysis.dart';
import '../train/skill_model.dart';
import 'game_review.dart';

/// What the player wants to go through after a game.
enum ReviewFocus {
  blunders('Blunders', 'The moves that cost the most'),
  mistakes('Mistakes', 'Smaller slips and inaccuracies'),
  wholeGame('Whole game', 'Every move you played, one by one');

  const ReviewFocus(this.label, this.detail);

  final String label;
  final String detail;
}

/// The player's moves to go through for [focus], in game order.
List<ReviewedMove> guidedSteps(GameReview review, ReviewFocus focus) {
  final mine = review.movesOf(review.game.playerSide);
  return switch (focus) {
    ReviewFocus.blunders => mine.where((m) => m.quality == MoveQuality.blunder).toList(),
    ReviewFocus.mistakes =>
      mine.where((m) => m.quality == MoveQuality.mistake || m.quality == MoveQuality.inaccuracy).toList(),
    ReviewFocus.wholeGame => mine.toList(),
  };
}

/// "13. Bf4 Nc6 14. Qd2" for [uci] moves played from [start], the position after [ply] moves.
/// Stops at the first move that isn't legal.
String sanLine(Position start, int ply, List<String> uci) {
  final out = StringBuffer();
  var pos = start;
  for (final (i, u) in uci.indexed) {
    final move = Move.parse(u);
    if (move == null || !pos.isLegal(move)) break;
    final n = ply + i;
    if (n.isEven) {
      out.write('${out.isEmpty ? '' : ' '}${n ~/ 2 + 1}. ');
    } else if (out.isEmpty) {
      out.write('${n ~/ 2 + 1}… ');
    } else {
      out.write(' ');
    }
    final (next, san) = pos.makeSan(move);
    out.write(san);
    pos = next;
  }
  return out.toString();
}

/// The mover's winning chances before and after [move], in plain words.
String chancesText(ReviewedMove move) {
  double win(Score s) => move.mover == Side.white ? s.whiteWinPercent : 100 - s.whiteWinPercent;
  final a = win(move.before).round(), b = win(move.after).round();
  if ((a - b).abs() < 3) return 'Your winning chances stay about the same ($b%).';
  return 'Your winning chances went from $a% to $b%.';
}

/// What the coach says about a move that wasn't an error.
String goodMoveText(ReviewedMove move) => switch (move.quality) {
      MoveQuality.best => 'The best move here. Exactly what the engine chose.',
      _ when move.bestSan != null && move.bestSan != move.san =>
        'A good move. ${move.bestSan} was a little stronger.',
      _ => 'A good move.',
    };

/// The habit that would have prevented this kind of error, for the part of the game it was in.
String nextTimeTip(ErrorKind kind, String phase) => switch (kind) {
      ErrorKind.allowsMate => 'Before every move, look at each check your opponent could give next, '
          'especially near your king. If one of them is mate, stop it first.',
      ErrorKind.missedMate => 'When the enemy king has few free squares, try every check you have. '
          'Look at checks first, then captures, then threats.',
      ErrorKind.losesPiece => 'Do a blunder check before you let go of the piece: after my move, what can my '
          'opponent take? Is every piece still protected?',
      ErrorKind.missedWin => 'On every move, look at all the captures for both sides. A piece that isn\'t '
          'protected can often be taken for free.',
      ErrorKind.worse => switch (phase) {
          Area.openings => 'In the opening, bring out your knights and bishops, fight for the centre and castle '
              'early. Try not to move the same piece twice.',
          Area.endgames => 'In the endgame, bring your king into the game and push your passed pawns. '
              'When you\'re ahead, trade pieces.',
          _ => 'Before you move, ask what your opponent wants to do next, then compare two or three '
              'candidate moves before you choose.',
        },
    };

/// The most common lesson from [steps]: the tip for the error kind that came up most.
String? mainLesson(List<ReviewedMove> steps, List<Position> positions) {
  final counts = <String, int>{};
  for (final m in steps) {
    final kind = m.errorKind;
    if (kind == null) continue;
    final tip = nextTimeTip(kind, phaseOf(positions[m.ply], m.ply));
    counts[tip] = (counts[tip] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
}
