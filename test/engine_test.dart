import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:chess_coach/coach/coach_player.dart';
import 'package:chess_coach/engine/analysis.dart';
import 'package:chess_coach/engine/chess_engine.dart';
import 'package:chess_coach/engine/engine_host.dart';
import 'package:chess_coach/engine/uci_process.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted engine: answers each command with canned output.
class FakeUci implements UciProcess {
  FakeUci(this.replies);

  final Map<String, List<String>> replies;
  final sent = <String>[];
  final _out = StreamController<String>.broadcast();

  @override
  Stream<String> get lines => _out.stream;

  @override
  void send(String command) {
    sent.add(command);
    for (final e in replies.entries) {
      if (command.startsWith(e.key)) {
        scheduleMicrotask(() => e.value.forEach(_out.add));
      }
    }
  }

  @override
  Future<void> close() async => _out.close();
}

const _start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const _blackToMove = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';

Analysis _analysis(String fen, List<(String, int)> moves) => Analysis(
      fen: fen,
      bestMove: moves.first.$1,
      lines: [
        for (final (i, (m, cp)) in moves.indexed)
          EngineLine(multipv: i + 1, depth: 10, score: Score.cp(cp), pv: [m]),
      ],
    );

void main() {
  group('UCI parsing', () {
    test('reads depth, multipv, score and pv', () {
      final l = parseInfo('info depth 12 seldepth 18 multipv 2 score cp 35 nodes 1000 pv e2e4 e7e5',
          whiteToMove: true)!;
      expect(l.depth, 12);
      expect(l.multipv, 2);
      expect(l.score, const Score.cp(35));
      expect(l.pv, ['e2e4', 'e7e5']);
    });

    test('converts black-to-move scores to White\'s view', () {
      final l = parseInfo('info depth 5 score mate 3 pv d8h4', whiteToMove: false)!;
      expect(l.score, const Score.mate(-3));
    });

    test('ignores lines without a pv', () {
      expect(parseInfo('info depth 1 currmove e2e4 currmovenumber 1', whiteToMove: true), isNull);
      expect(parseInfo('info string NNUE evaluation enabled', whiteToMove: true), isNull);
    });

    test('score helpers', () {
      expect(const Score.cp(0).whiteWinPercent, closeTo(50, 0.01));
      expect(const Score.cp(300).whiteWinPercent, greaterThan(70));
      expect(const Score.mate(2).label, 'M2');
      expect(const Score.cp(-150).label, '-1.5');
      expect(const Score.mate(1).compareTo(const Score.cp(900)), greaterThan(0));
    });
  });

  group('ChessEngine', () {
    test('runs handshake and returns sorted lines', () async {
      final fake = FakeUci({
        'uci': ['id name Fake', 'uciok'],
        'isready': ['readyok'],
        'go': [
          'info depth 8 multipv 2 score cp 10 pv d2d4',
          'info depth 8 multipv 1 score cp 30 pv e2e4 e7e5',
          'bestmove e2e4 ponder e7e5',
        ],
      });
      final engine = await ChessEngine.start(process: fake);
      final a = await engine.analyse(_start, depth: 8, multiPv: 2);
      expect(a.bestMove, 'e2e4');
      expect(a.lines.map((l) => l.move), ['e2e4', 'd2d4']);
      expect(fake.sent, contains('setoption name MultiPV value 2'));
      expect(fake.sent, contains('go depth 8'));
    });

    test('queues searches in order', () async {
      final fake = FakeUci({
        'uci': ['uciok'],
        'isready': ['readyok'],
        'go': ['info depth 1 score cp 1 pv a2a3', 'bestmove a2a3'],
      });
      final engine = await ChessEngine.start(process: fake);
      final results = await Future.wait([engine.analyse(_start), engine.analyse(_blackToMove)]);
      expect(results.map((r) => r.fen), [_start, _blackToMove]);
      expect(fake.sent.where((c) => c.startsWith('position')).toList(),
          ['position fen $_start', 'position fen $_blackToMove']);
    });

    test('handles whitespace-tolerant FENs', () async {
      final fake = FakeUci({
        'uci': ['uciok'],
        'isready': ['readyok'],
        'go': ['info depth 1 score cp 10 pv e2e4', 'bestmove e2e4'],
      });
      final engine = await ChessEngine.start(process: fake);
      const multiSpaceFen = '  rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR   w   KQkq   -   0   1  ';
      final a = await engine.analyse(multiSpaceFen, depth: 1);
      expect(a.bestMove, 'e2e4');
      await engine.dispose();
    });

    test('sends stop to engine if search throws or times out', () async {
      final fake = FakeUci({
        'uci': ['uciok'],
        'isready': ['readyok'],
      });
      final engine = await ChessEngine.start(process: fake);
      await expectLater(
        engine.analyse(_start, searchTimeout: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
      expect(fake.sent, contains('stop'));
      await engine.dispose();
    });

    test('EngineHost.dispose disposes status notifier', () async {
      final fake = FakeUci({'uci': ['uciok'], 'isready': ['readyok']});
      final host = EngineHost(starter: () => ChessEngine.start(process: fake));
      final engine = await host.engine;
      expect(engine, isNotNull);
      expect(host.status.value, EngineStatus.ready);
      await host.dispose();
      expect(() => host.status.addListener(() {}), throwsFlutterError);
    });
  });

  group('human-like move choice', () {
    final a = _analysis(_start, [('e2e4', 40), ('d2d4', 35), ('g1f3', 30), ('a2a4', -60), ('g2g4', -150)]);

    test('a strong coach mostly plays the best move and never a bad one', () {
      final rnd = math.Random(1);
      final picks = List.generate(200, (_) => pickHumanMove(a, 2800, rnd));
      expect(picks.where((m) => m == 'e2e4').length, greaterThan(160));
      expect(picks.where((m) => m == 'a2a4' || m == 'g2g4'), isEmpty);
    });

    test('a beginner coach varies and sometimes errs, but only among candidates', () {
      final rnd = math.Random(2);
      final picks = List.generate(400, (_) => pickHumanMove(a, 600, rnd)).toSet();
      expect(picks.length, greaterThanOrEqualTo(4));
      expect(picks.every((m) => a.lines.any((l) => l.move == m)), isTrue);
    });

    test('works for Black too', () {
      final b = _analysis(_blackToMove, [('e7e5', -30), ('h7h5', 120)]);
      final rnd = math.Random(3);
      final picks = List.generate(100, (_) => pickHumanMove(b, 2400, rnd));
      expect(picks.where((m) => m == 'e7e5').length, greaterThan(95));
    });
  });

  group('move grading', () {
    test('thresholds', () {
      MoveQuality g(int before, int after) => classifyMove(
          before: Score.cp(before), after: Score.cp(after), moverIsWhite: true, playedBest: false);
      expect(g(30, 25), MoveQuality.best);
      expect(g(30, -20), MoveQuality.good);
      expect(g(0, -150), MoveQuality.inaccuracy);
      expect(g(0, -300), MoveQuality.mistake);
      expect(g(0, -600), MoveQuality.blunder);
    });

    test('from Black\'s side', () {
      expect(
          classifyMove(
              before: const Score.cp(0), after: const Score.cp(600), moverIsWhite: false, playedBest: false),
          MoveQuality.blunder);
    });
  });

  test('real Stockfish finds mate in one', () async {
    final path = '${Directory.current.path}/engines/linux/stockfish';
    if (!Platform.isLinux || !File(path).existsSync()) {
      markTestSkipped('Stockfish binary not fetched');
      return;
    }
    final engine = await ChessEngine.start(process: await DesktopUciProcess.start(path));
    final a = await engine.analyse('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1', depth: 10);
    expect(a.bestMove, 'a1a8');
    expect(a.score, const Score.mate(1));
    await engine.dispose();
  });
}
