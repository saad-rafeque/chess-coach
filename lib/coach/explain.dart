import 'package:dartchess/dartchess.dart';

import '../engine/analysis.dart';
import 'coach_player.dart';

/// SAN for a UCI move in [pos], or the UCI string if it can't be played.
String sanOf(Position pos, String uci) {
  final m = Move.parse(uci);
  if (m == null || !pos.isLegal(m)) return uci;
  return pos.makeSan(m).$2;
}

/// What kind of error a move was, which decides the advice for next time.
enum ErrorKind { allowsMate, missedMate, losesPiece, missedWin, worse }

/// Explains why the player's move was an error; see [explainErrorInsight].
String explainError({
  required MoveQuality quality,
  required Position before,
  required Analysis beforeAnalysis,
  required Position after,
  required Analysis afterAnalysis,
}) =>
    explainErrorInsight(
      quality: quality,
      before: before,
      beforeAnalysis: beforeAnalysis,
      after: after,
      afterAnalysis: afterAnalysis,
    ).text;

/// Explains why the player's move was an error, using facts from the engine:
/// what the opponent can now do, or what the player missed.
///
/// [before] is the position before the move with its analysis, [after] the
/// position after the move with its analysis (opponent to move).
({ErrorKind kind, String text}) explainErrorInsight({
  required MoveQuality quality,
  required Position before,
  required Analysis beforeAnalysis,
  required Position after,
  required Analysis afterAnalysis,
}) {
  final me = before.turn;
  final best = beforeAnalysis.bestMove;
  final bestSan = best == null ? null : sanOf(before, best);
  final better = bestSan == null ? '' : ' Better was $bestSan.';

  // The opponent can now mate.
  final afterScore = afterAnalysis.score;
  if (afterScore?.mate != null) {
    final mateForOpponent = me == Side.white ? afterScore!.mate! < 0 : afterScore!.mate! > 0;
    if (mateForOpponent) {
      final n = afterScore.mate!.abs();
      return (kind: ErrorKind.allowsMate, text: 'This allows checkmate in $n.$better');
    }
  }

  // The player missed a mate.
  final beforeScore = beforeAnalysis.score;
  if (beforeScore?.mate != null && bestSan != null) {
    final mateForMe = me == Side.white ? beforeScore!.mate! > 0 : beforeScore!.mate! < 0;
    if (mateForMe) return (kind: ErrorKind.missedMate, text: 'You missed a checkmate: $bestSan.');
  }

  // The opponent's best reply wins material.
  final reply = afterAnalysis.bestMove == null ? null : Move.parse(afterAnalysis.bestMove!);
  if (reply is NormalMove) {
    final victim = after.board.pieceAt(reply.to);
    if (victim != null && victim.color == me && victim.role != Role.pawn) {
      return (
        kind: ErrorKind.losesPiece,
        text: 'Now ${_side(me.opposite)} can take your ${victim.role.name} on ${reply.to.name}.$better',
      );
    }
  }

  // The player missed winning material.
  if (best != null) {
    final m = Move.parse(best);
    if (m is NormalMove) {
      final target = before.board.pieceAt(m.to);
      if (target != null && target.color != me) {
        return (kind: ErrorKind.missedWin, text: 'You missed $bestSan, which wins a ${target.role.name}.');
      }
    }
  }

  return (
    kind: ErrorKind.worse,
    text: switch (quality) {
      MoveQuality.blunder => 'This loses a lot.$better',
      MoveQuality.mistake => 'This makes your position clearly worse.$better',
      _ => 'There was a stronger move.$better',
    },
  );
}

String _side(Side s) => s == Side.white ? 'White' : 'Black';
