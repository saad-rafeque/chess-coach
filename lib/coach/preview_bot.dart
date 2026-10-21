import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

const pieceValue = {
  Role.pawn: 1,
  Role.knight: 3,
  Role.bishop: 3,
  Role.rook: 5,
  Role.queen: 9,
  Role.king: 0,
};

List<NormalMove> legalMoves(Position pos) => [
      for (final e in pos.legalMoves.entries)
        for (final to in e.value.squares) _withAutoQueen(pos, NormalMove(from: e.key, to: to)),
    ];

NormalMove _withAutoQueen(Position pos, NormalMove m) {
  final piece = pos.board.pieceAt(m.from);
  final lastRank = m.to.rank == Rank.first || m.to.rank == Rank.eighth;
  return piece?.role == Role.pawn && lastRank ? m.withPromotion(Role.queen) : m;
}

/// The undefended enemy piece that [move] captures, if any.
Piece? freeCapture(Position pos, NormalMove move) {
  final target = pos.board.pieceAt(move.to);
  if (target == null || target.color == pos.turn) return null;
  final after = pos.playUnchecked(move);
  return after.board.attacksTo(move.to, pos.turn.opposite).isEmpty ? target : null;
}

/// One-ply practice opponent: grabs material, avoids hanging pieces, with some
/// randomness. Placeholder until the Maia coach lands in milestone 2.
NormalMove? pickPreviewMove(Position pos, math.Random rnd) {
  final moves = legalMoves(pos);
  if (moves.isEmpty) return null;
  NormalMove? best;
  var bestScore = double.negativeInfinity;
  for (final m in moves) {
    final after = pos.playUnchecked(m);
    var score = rnd.nextDouble() * 2;
    if (after.isCheckmate) score += 1000;
    if (after.isCheck) score += 0.5;
    final captured = pos.board.pieceAt(m.to);
    if (captured != null && captured.color != pos.turn) score += pieceValue[captured.role]! * 10;
    final moved = after.board.pieceAt(m.to);
    if (moved != null && moved.color == pos.turn) {
      final attacked = after.board.attacksTo(m.to, pos.turn.opposite).isNotEmpty;
      final defended = after.board.attacksTo(m.to, pos.turn).isNotEmpty;
      if (attacked && !defended) score -= pieceValue[moved.role]! * 9;
    }
    if (score > bestScore) {
      bestScore = score;
      best = m;
    }
  }
  return best ?? moves.first;
}
