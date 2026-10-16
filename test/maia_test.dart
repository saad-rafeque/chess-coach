import 'dart:io' as io;
import 'dart:math' as math;

import 'package:chess_coach/engine/engine_host.dart';
import 'package:chess_coach/game/game_controller.dart';
import 'package:chess_coach/maia/maia_net.dart';
import 'package:chess_coach/maia/maia_player.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

List<Position> _history(List<String> moves) {
  final list = <Position>[Chess.initial];
  for (final m in moves) {
    list.add(list.last.play(Move.parse(m)!));
  }
  return list;
}

Map<String, double> _top(MaiaNet net, List<Position> history) =>
    {for (final e in net.policy(history).entries) e.key.uci: e.value};

void main() {
  late MaiaNet net;

  setUpAll(() {
    net = MaiaNet.fromGzip(io.File('assets/maia/maia-1100.pb.gz').readAsBytesSync());
  });

  // Expected values come from a numpy reference implementation of the same network.
  test('opening move probabilities match the reference', () {
    final p = _top(net, _history(const []));
    expect(p['e2e4'], closeTo(0.66056, 0.005));
    expect(p['d2d4'], closeTo(0.20977, 0.005));
    expect(p.values.reduce((a, b) => a + b), closeTo(1, 1e-6));
    expect(p, hasLength(20));
  });

  test('Black is seen from its own side', () {
    final p = _top(net, _history(const ['e2e4']));
    expect(p['e7e5'], closeTo(0.58633, 0.005));
    expect(p['c7c5'], closeTo(0.11136, 0.005));
  });

  test('castling uses the king-to-rook encoding, for both colours', () {
    final white = _top(net, _history(const ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g8f6', 'd2d3', 'f8c5']));
    expect(white['f3g5'], closeTo(0.32061, 0.005));
    expect(white['e1h1'], closeTo(0.21244, 0.005));
    final black = _top(net,
        _history(const ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5', 'c2c3', 'g8f6', 'd2d3', 'd7d6', 'e1g1']));
    expect(black['c8g4'], closeTo(0.3722, 0.005));
    expect(black['e8h8'], closeTo(0.30799, 0.005));
  });

  test('takes a hanging queen most of the time', () {
    final p = _top(net, [Chess.fromSetup(Setup.parseFen('4k3/8/8/r2Q4/8/8/8/4K3 b - - 0 1'))]);
    expect(p['a5d5'], closeTo(0.57518, 0.005));
  });

  test('promotions get every piece choice', () {
    final p = _top(net, [Chess.fromSetup(Setup.parseFen('8/P6k/8/8/8/8/8/K7 w - - 0 1'))]);
    expect(p.keys.where((k) => k.startsWith('a7a8')), hasLength(4));
  });

  test('move planes', () {
    expect(movePlane(NormalMove.fromUci('e2e4'), black: false), 1); // N, 2 steps
    expect(movePlane(NormalMove.fromUci('g1f3'), black: false), 56 + 7); // knight NW
    expect(movePlane(NormalMove.fromUci('e7e5'), black: true), 1);
    expect(movePlane(NormalMove.fromUci('a7a8q'), black: false), 64 + 3 + 2);
  });

  group('MaiaPlayer', () {
    final player = MaiaPlayer(loader: (r) async => io.File('assets/maia/maia-$r.pb.gz').readAsBytesSync());

    test('picks the nearest net and loosens below 1100', () {
      expect(MaiaPlayer.netFor(400), 1100);
      expect(MaiaPlayer.netFor(1449), 1400);
      expect(MaiaPlayer.netFor(1450), 1500);
      expect(MaiaPlayer.netFor(2500), 1900);
      expect(MaiaPlayer.temperatureFor(1500), 1.0);
      expect(MaiaPlayer.temperatureFor(600), greaterThan(MaiaPlayer.temperatureFor(1000)));
    });

    test('plays legal, human-like opening moves', () async {
      final rnd = math.Random(4);
      final picks = <String>{};
      for (var i = 0; i < 6; i++) {
        picks.add((await player.pick(const [], 1500, rnd))!.uci);
      }
      expect(picks.every((m) => Chess.initial.isLegal(Move.parse(m)!)), isTrue);
      expect(picks.intersection({'e2e4', 'd2d4', 'c2c4', 'g1f3'}), isNotEmpty);
    });

    test('a low temperature sharpens the choice', () {
      final probs = {NormalMove.fromUci('e2e4'): 0.6, NormalMove.fromUci('a2a3'): 0.4};
      final rnd = math.Random(1);
      final sharp = List.generate(200, (_) => sampleMove(probs, 0.1, rnd).uci).where((m) => m == 'e2e4').length;
      expect(sharp, greaterThan(185)); // 0.6^10 vs 0.4^10: about 98%
    });

    test('the coach uses Maia without Stockfish', () async {
      final offline = EngineHost(starter: () => Future.error(UnsupportedError('none')));
      final g = GameController(host: offline, maia: player)..newGame(side: Side.black, elo: 800);
      for (var i = 0; i < 100 && g.moves.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(g.moves, hasLength(1));
      expect(g.chat.any((m) => m.text.contains('simple rules')), isFalse);
    });
  });
}
