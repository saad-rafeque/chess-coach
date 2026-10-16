import 'package:dartchess/dartchess.dart';

enum TipKind { good, warning, info }

class Tip {
  const Tip(this.text, this.kind);

  final String text;
  final TipKind kind;
}

const _value = {
  Role.pawn: 1,
  Role.knight: 3,
  Role.bishop: 3,
  Role.rook: 5,
  Role.queen: 9,
  Role.king: 100,
};

/// Rule-based comment on the move just played. Stand-in for the engine-backed
/// coach (milestone 2); always returns the single most useful tip, or null.
Tip? tipForMove(Position before, NormalMove move, Position after) {
  final piece = before.board.pieceAt(move.from);
  if (piece == null) return null;
  final me = piece.color;
  final captured = before.board.pieceAt(move.to);
  final castled = piece.role == Role.king &&
      ((move.from.file - move.to.file).abs() >= 2 || captured?.color == me);

  if (after.isCheckmate) return const Tip('Checkmate! Brilliant finish.', TipKind.good);
  if (after.isStalemate) {
    return const Tip('Stalemate: the game is a draw. When winning, always leave the king a move.',
        TipKind.warning);
  }

  if (!castled) {
    final dest = move.to;
    final attackers = after.board.attacksTo(dest, me.opposite).squares.toList();
    if (attackers.isNotEmpty && piece.role != Role.king) {
      final defended = after.board.attacksTo(dest, me).isNotEmpty;
      final cheapest = attackers
          .map((s) => _value[after.board.pieceAt(s)!.role]!)
          .reduce((a, b) => a < b ? a : b);
      if (!defended) {
        return Tip(
            'Careful: your ${piece.role.name} on ${dest.name} can be taken for free. '
            'Before every move, check that the piece is safe.',
            TipKind.warning);
      }
      if (cheapest < _value[piece.role]!) {
        return Tip(
            'Your ${piece.role.name} on ${dest.name} can be captured by a cheaper piece. '
            'That trade loses material.',
            TipKind.warning);
      }
    }
  }

  if (after.isCheck) {
    return const Tip('Check! Checks are strongest when they also improve your position.', TipKind.info);
  }
  if (castled) return const Tip('Great: castling keeps your king safe and connects your rooks.', TipKind.good);
  if (captured != null && captured.color != me) {
    return Tip('You won a ${captured.role.name}.', TipKind.good);
  }

  final opening = before.fullmoves <= 8;
  if (!opening) return null;
  final backRank = me == Side.white ? Rank.first : Rank.eighth;
  if (piece.role == Role.queen && before.fullmoves <= 4) {
    return const Tip(
        'Bringing the queen out early lets your opponent chase it with tempo. '
        'Develop knights and bishops first.',
        TipKind.warning);
  }
  if (piece.role == Role.king) {
    return const Tip('Moving the king early loses the right to castle.', TipKind.warning);
  }
  if ((piece.role == Role.knight || piece.role == Role.bishop) && move.from.rank == backRank) {
    return Tip('Good development: your ${piece.role.name} joins the game.', TipKind.good);
  }
  if (piece.role == Role.pawn) {
    if (move.to.file == File.d || move.to.file == File.e) {
      if (before.fullmoves <= 3) {
        return const Tip('A centre pawn: it controls key squares and frees your pieces.', TipKind.good);
      }
    } else if (move.to.file == File.a || move.to.file == File.h) {
      return const Tip('Edge pawn moves rarely help in the opening. Focus on the centre.', TipKind.info);
    }
  }
  return null;
}
