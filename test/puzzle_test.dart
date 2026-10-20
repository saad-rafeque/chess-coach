import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;

import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/puzzles/mistakes.dart';
import 'package:chess_coach/puzzles/puzzle.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

// A real Lichess puzzle shape: Black plays ...Qxe5?? and White wins the queen with a fork.
// Setup move first, then the solution (one player move here).
const _line = 'tst01\tr1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2\t'
    'd8h4 f3h4\t700\tfork short';

PuzzleSession _session(String line, {void Function(PuzzleItem, bool)? onResult}) =>
    PuzzleSession(PuzzleItem.parse(line)!, onResult: onResult, moveDelay: Duration.zero);

void main() {
  test('parses a puzzle line', () {
    final p = PuzzleItem.parse(_line)!;
    expect(p.id, 'tst01');
    expect(p.moves, ['d8h4', 'f3h4']);
    expect(p.rating, 700);
    expect(p.namedThemes, ['Fork']);
  });

  test('plays the setup move, then accepts the right answer', () async {
    final results = <bool>[];
    final s = _session(_line, onResult: (_, ok) => results.add(ok));
    expect(s.playerSide, Side.white);
    await s.start();
    expect(s.state, PuzzleState.playerToMove);
    expect(s.lastMove?.uci, 'd8h4');
    expect(await s.playerMove(NormalMove.fromUci('f3h4')), isTrue);
    expect(s.state, PuzzleState.solved);
    expect(results, [true]);
  });

  test('a wrong move counts as a failure once, but you can still finish', () async {
    final results = <bool>[];
    final s = _session(_line, onResult: (_, ok) => results.add(ok));
    await s.start();
    expect(await s.playerMove(NormalMove.fromUci('a2a3')), isFalse);
    expect(s.state, PuzzleState.wrongMove);
    expect(await s.playerMove(NormalMove.fromUci('f3h4')), isTrue);
    expect(results, [false]);
  });

  test('multi-move puzzles: the opponent replies between your moves', () async {
    // Scholar's mate pattern spread over two player moves.
    const line = 'tst02\trnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2\t'
        'f1c4 b8c6 d1h5 g8f6 h5f7\t600\tmateIn2';
    final s = _session(line);
    await s.start();
    expect(s.playerSide, Side.black);
    expect(await s.playerMove(NormalMove.fromUci('b8c6')), isTrue);
    expect(s.position.board.pieceAt(Square.h5)?.role, Role.queen);
    expect(await s.playerMove(NormalMove.fromUci('g8f6')), isTrue);
    expect(s.state, PuzzleState.playerToMove);
  });

  test('any checkmate is accepted on the last move', () async {
    // White to move (no setup): both Qa8# and Qh8#... here only one mates; accept the mate.
    const p = PuzzleItem(
        id: 'm1', fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1', moves: ['a1a8'], rating: 600, themes: ['mateIn1'], setup: false);
    final s = PuzzleSession(p, moveDelay: Duration.zero);
    await s.start();
    expect(await s.playerMove(NormalMove.fromUci('a1a8')), isTrue);
  });

  test('early checkmate is accepted and marks puzzle solved immediately', () async {
    const p = PuzzleItem(
      id: 'early_mate',
      fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
      moves: ['a1a8', 'g8f7', 'a8f8'],
      rating: 700,
      themes: ['mate'],
      setup: false,
    );
    final results = <bool>[];
    final s = PuzzleSession(p, onResult: (_, ok) => results.add(ok), moveDelay: Duration.zero);
    await s.start();
    expect(await s.playerMove(NormalMove.fromUci('a1a8')), isTrue);
    expect(s.state, PuzzleState.solved);
    expect(results, [true]);
  });

  test('show solution plays the line and counts as failed', () async {
    final results = <bool>[];
    final s = _session(_line, onResult: (_, ok) => results.add(ok));
    await s.start();
    await s.showSolution();
    expect(s.lastMove?.uci, 'f3h4');
    expect(results, [false]);
  });

  test('bank picks puzzles near your rating and skips seen ones', () {
    final bank = PuzzleBank([
      for (var r = 400; r < 2400; r += 50)
        PuzzleItem(id: 'p$r', fen: '', moves: const ['a2a3'], rating: r, themes: [(r ~/ 50).isEven ? 'fork' : 'pin']),
    ]);
    final rnd = math.Random(1);
    for (var i = 0; i < 20; i++) {
      final p = bank.next(rating: 1000, random: rnd)!;
      expect(p.rating, inInclusiveRange(940, 1100));
    }
    expect(bank.next(rating: 1000, exclude: {for (final p in bank.puzzles) if (p.id != 'p2350') p.id})!.id, 'p2350');
    expect(bank.next(rating: 1000, theme: 'pin', random: rnd)!.themes, ['pin']);
  });

  test('bank loads from a gzipped file', () {
    final bytes = io.GZipCodec().encode(utf8.encode('$_line\n'));
    expect(PuzzleBank.fromGzip(bytes).puzzles.single.id, 'tst01');
  });

  test('stats: rating moves with results, streak counts days', () {
    final now = DateTime(2026, 10, 16, 12);
    AppEvent e(String id, bool ok, int daysAgo) => AppEvent(
        id: id,
        type: puzzleEventType,
        time: now.subtract(Duration(days: daysAgo)).toUtc(),
        device: 'd',
        data: {'id': id, 'solved': ok, 'puzzleRating': 900, 'rated': true});
    final stats = PuzzleStats.fromEvents([e('a', true, 2), e('b', true, 1), e('c', true, 0), e('d', false, 0)], today: now);
    expect(stats.solved, 3);
    expect(stats.attempted, 4);
    expect(stats.streakDays, 3);
    expect(stats.seen, {'a', 'b', 'c', 'd'});
    expect(stats.rating.rating, greaterThan(900));
  });

  test('mistakes from reviewed games become puzzles', () async {
    final store = await storeWithReviewedGame();
    final puzzles = mistakePuzzles(store);
    expect(puzzles, hasLength(1));
    expect(puzzles.single.moves, ['g7g6']);
    expect(puzzles.single.setup, isFalse);
    expect(Chess.fromSetup(Setup.parseFen(puzzles.single.fen)).turn, Side.black);
  });

  test('bundled puzzle set is valid (every 10th puzzle replayed)', () {
    final bank = PuzzleBank.fromGzip(io.File('assets/puzzles/puzzles.tsv.gz').readAsBytesSync());
    expect(bank.puzzles.length, greaterThan(20000));
    for (var i = 0; i < bank.puzzles.length; i += 10) {
      final p = bank.puzzles[i];
      Position pos = Chess.fromSetup(Setup.parseFen(p.fen));
      for (final m in p.moves) {
        final move = Move.parse(m)!;
        expect(pos.isLegal(move), isTrue, reason: '${p.id}: $m');
        pos = pos.play(move);
      }
      expect(p.moves.length.isEven, isTrue, reason: '${p.id} ends on the player\'s move');
    }
    expect(bank.byTheme['fork']!.length, greaterThan(1000));
  });
}
