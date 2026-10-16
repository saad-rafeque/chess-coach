import 'dart:math' as math;

import 'package:chess_coach/coach/preview_bot.dart';
import 'package:chess_coach/coach/quick_tips.dart';
import 'package:chess_coach/data/puzzles.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

Position _fen(String fen) => Chess.fromSetup(Setup.parseFen(fen));

Position _play(List<String> uci) {
  Position p = Chess.initial;
  for (final m in uci) {
    p = p.play(NormalMove.fromUci(m));
  }
  return p;
}

Tip? _tip(Position before, String uci) {
  final m = NormalMove.fromUci(uci);
  return tipForMove(before, m, before.play(m));
}

void main() {
  group('starter puzzles', () {
    for (final pz in starterPuzzles) {
      test('${pz.theme} solution is legal and reaches its goal', () {
        final pos = _fen(pz.fen);
        final move = NormalMove.fromUci(pz.solution);
        expect(pos.isLegal(move), isTrue);
        final after = pos.play(move);
        if (pz.goal == PuzzleGoal.mate) {
          expect(after.isCheckmate, isTrue);
        } else {
          expect(after.isCheck, isTrue);
        }
      });
    }
  });

  group('quick tips', () {
    test('praises a centre pawn on move one', () {
      expect(_tip(Chess.initial, 'e2e4')!.kind, TipKind.good);
    });

    test('praises knight development', () {
      expect(_tip(Chess.initial, 'g1f3')!.text, contains('development'));
    });

    test('warns about an early queen', () {
      final t = _tip(_play(['e2e4', 'e7e5']), 'd1h5')!;
      expect(t.kind, TipKind.warning);
      expect(t.text, contains('queen'));
    });

    test('warns about a hanging piece', () {
      final t = _tip(_play(['e2e4', 'e7e5']), 'f1a6')!;
      expect(t.kind, TipKind.warning);
      expect(t.text, contains('free'));
    });

    test('praises castling', () {
      final pos = _fen('r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4');
      expect(_tip(pos, 'e1g1')!.text, contains('castling'));
    });

    test('recognises checkmate', () {
      final pos = _fen(starterPuzzles.first.fen);
      expect(_tip(pos, 'h5f7')!.text, contains('Checkmate'));
    });
  });

  group('preview bot', () {
    test('finds all 20 opening moves', () {
      expect(legalMoves(Chess.initial), hasLength(20));
    });

    test('takes a free queen', () {
      final pos = _fen('4k3/8/8/r2Q4/8/8/8/4K3 b - - 0 1');
      final move = pickPreviewMove(pos, math.Random(1));
      expect(move.uci, 'a5d5');
    });

    test('always returns a legal move', () {
      final rnd = math.Random(3);
      Position pos = Chess.initial;
      for (var i = 0; i < 60 && !pos.isGameOver; i++) {
        final m = pickPreviewMove(pos, rnd);
        expect(pos.isLegal(m), isTrue);
        pos = pos.play(m);
      }
    });
  });
}
