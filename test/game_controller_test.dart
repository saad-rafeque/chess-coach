import 'dart:async';
import 'dart:convert';

import 'package:chess_coach/coach/coach_player.dart';
import 'package:chess_coach/engine/chess_engine.dart';
import 'package:chess_coach/engine/analysis.dart';
import 'package:chess_coach/engine/engine_host.dart';
import 'package:chess_coach/engine/uci_process.dart';
import 'package:chess_coach/data/game_record.dart';
import 'package:chess_coach/game/game_controller.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

/// Engine that plays the first legal move and scores positions with [score]
/// (centipawns from White's point of view).
class ScriptedEngine implements UciProcess {
  ScriptedEngine([this.score]);

  final int Function(Position pos)? score;
  final _out = StreamController<String>.broadcast();
  Position _pos = Chess.initial;

  @override
  Stream<String> get lines => _out.stream;

  @override
  void send(String c) {
    void emit(List<String> l) => scheduleMicrotask(() => l.forEach(_out.add));
    if (c == 'uci') emit(['uciok']);
    if (c == 'isready') emit(['readyok']);
    if (c.startsWith('position fen '))
      _pos = Chess.fromSetup(Setup.parseFen(c.substring(13)));
    if (c.startsWith('go')) {
      final entry = _pos.legalMoves.entries.firstWhere(
        (e) => e.value.isNotEmpty,
      );
      final uci = NormalMove(
        from: entry.key,
        to: entry.value.squares.first,
      ).uci;
      final white = score?.call(_pos) ?? 0;
      final cp = _pos.turn == Side.white ? white : -white;
      emit(['info depth 12 multipv 1 score cp $cp pv $uci', 'bestmove $uci']);
    }
  }

  @override
  Future<void> close() async => _out.close();
}

class FailingSearchUci extends ScriptedEngine {
  @override
  void send(String command) {
    if (command.startsWith('go')) throw StateError('simulated search failure');
    super.send(command);
  }
}

class PendingAnalysisEngine implements ChessEngine {
  final requests = <({String fen, Completer<Analysis> result})>[];
  @override
  bool isClosed = false;

  @override
  Future<Analysis> analyse(
    String fen, {
    int depth = 14,
    Duration? movetime,
    int multiPv = 1,
    Duration searchTimeout = const Duration(seconds: 60),
  }) {
    final result = Completer<Analysis>();
    requests.add((fen: fen, result: result));
    return result.future;
  }

  void finish(int index) {
    final request = requests[index];
    final pos = Chess.fromSetup(Setup.parseFen(request.fen));
    final entry = pos.legalMoves.entries.firstWhere((e) => e.value.isNotEmpty);
    final move = NormalMove(from: entry.key, to: entry.value.squares.first).uci;
    request.result.complete(
      Analysis(
        fen: request.fen,
        bestMove: move,
        lines: [
          EngineLine(
            multipv: 1,
            depth: 12,
            score: const Score.cp(0),
            pv: [move],
          ),
        ],
      ),
    );
  }

  @override
  Future<void> dispose() async {
    isClosed = true;
  }
}

EngineHost _host([int Function(Position)? score]) => EngineHost(
  starter: () => ChessEngine.start(process: ScriptedEngine(score)),
);

final _offline = EngineHost(
  starter: () => Future.error(UnsupportedError('none')),
);

Future<void> _untilCoachMoved(GameController g) async {
  for (
    var i = 0;
    i < 100 && (g.thinking || g.position.turn != g.playerSide);
    i++
  ) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  test(
    'a hint waiting for engine startup cannot leak into a new game',
    () async {
      final ready = Completer<ChessEngine>();
      final host = EngineHost(starter: () => ready.future);
      final engine = PendingAnalysisEngine();
      final g = GameController(host: host)
        ..newGame(side: Side.white, elo: 800, twoPlayers: true);
      final hint = g.hint();
      g.newGame(side: Side.white, elo: 800, twoPlayers: true);
      ready.complete(engine);
      await hint;
      expect(engine.requests, isEmpty);
      expect(g.highlight, isNull);
      expect(g.chat.where((m) => m.text.startsWith('Hint:')), isEmpty);
      g.dispose();
      await host.dispose();
    },
  );

  for (final action in [
    'new game',
    'real mode',
    'undo',
    'resign',
    'move',
    'dispose',
  ]) {
    test('pending hint is cancelled by $action', () async {
      final engine = PendingAnalysisEngine();
      final host = EngineHost(starter: () async => engine);
      final g = GameController(host: host);
      if (action != 'real mode') {
        g.newGame(side: Side.white, elo: 800, twoPlayers: true);
      }
      if (['undo', 'resign', 'move'].contains(action)) {
        await g.playerMove(NormalMove.fromUci('e2e4'));
      }
      final hint = g.hint();
      await Future<void>.delayed(Duration.zero);
      expect(engine.requests, hasLength(1));
      switch (action) {
        case 'new game':
          g.newGame(side: Side.white, elo: 800, twoPlayers: true);
        case 'real mode':
          g.setMode(PlayMode.real);
        case 'undo':
          g.undo();
        case 'resign':
          g.resign();
        case 'move':
          await g.playerMove(NormalMove.fromUci('e7e5'));
        case 'dispose':
          g.dispose();
      }
      engine.finish(0);
      await hint;
      expect(g.highlight, isNull);
      expect(g.arrow, isNull);
      expect(g.chat.where((m) => m.text.startsWith('Hint:')), isEmpty);
      if (action == 'real mode') {
        await g.hint();
        expect(
          engine.requests,
          hasLength(1),
          reason: 'Real game does not allow hints',
        );
      }
      if (action != 'dispose') g.dispose();
      await host.dispose();
    });
  }

  test(
    'rapid hint taps share one request without skipping the first hint level',
    () async {
      final engine = PendingAnalysisEngine();
      final host = EngineHost(starter: () async => engine);
      final g = GameController(host: host)
        ..newGame(side: Side.white, elo: 800, twoPlayers: true);
      final first = g.hint();
      final second = g.hint();
      final third = g.hint();
      await Future<void>.delayed(Duration.zero);
      expect(engine.requests, hasLength(1));
      engine.finish(0);
      await Future.wait([first, second, third]);
      expect(g.chat.where((m) => m.text.startsWith('Hint:')), hasLength(1));
      expect(g.highlight, isNotNull);
      expect(g.arrow, isNull);
      await g.hint();
      expect(g.arrow, isNotNull);
      expect(
        engine.requests,
        hasLength(1),
        reason: 'the completed analysis is reused',
      );
      g.dispose();
      await host.dispose();
    },
  );

  test(
    'current Coach guidance clears a previous-turn hint but preserves chat',
    () async {
      final g = GameController(host: _offline)
        ..newGame(side: Side.white, elo: 800, twoPlayers: true);
      await g.playerMove(NormalMove.fromUci('e2e4'));
      await g.hint();
      final oldHint = g.currentGuidance;
      expect(oldHint, startsWith('Hint: Black:'));
      await g.playerMove(NormalMove.fromUci('e7e5'));
      expect(g.currentGuidance, startsWith('White to move.'));
      expect(g.currentGuidance, isNot(oldHint));
      expect(g.chat.any((m) => m.text == oldHint), isTrue);
      g.dispose();
    },
  );

  test(
    'failed engine startup cannot append stale move feedback to a new game',
    () async {
      final ready = Completer<ChessEngine>();
      final host = EngineHost(starter: () => ready.future);
      final g = GameController(host: host)..newGame(side: Side.white, elo: 800);
      final move = g.playerMove(NormalMove.fromUci('e2e4'));
      g.newGame(side: Side.white, elo: 800, twoPlayers: true);
      final welcome = g.chat.single.text;
      ready.completeError(StateError('startup failed'));
      await move;
      expect(g.chat.map((m) => m.text), [welcome]);
      expect(g.moves, isEmpty);
      expect(g.grades, isEmpty);
      g.dispose();
      await host.dispose();
    },
  );

  test(
    'stale move analysis stops before requesting the next position',
    () async {
      final engine = PendingAnalysisEngine();
      final host = EngineHost(starter: () async => engine);
      final g = GameController(host: host);
      final move = g.playerMove(NormalMove.fromUci('e2e4'));
      await Future<void>.delayed(Duration.zero);
      expect(engine.requests, hasLength(1));
      g.newGame(side: Side.white, elo: 800, twoPlayers: true);
      engine.finish(0);
      await move;
      expect(engine.requests, hasLength(1));
      expect(g.grades, isEmpty);
      expect(g.chat, hasLength(1));
      g.dispose();
      await host.dispose();
    },
  );

  test(
    'without an engine the coach still replies and gives rule-based tips',
    () async {
      final g = GameController(host: _offline)
        ..newGame(side: Side.white, elo: 800);
      await g.playerMove(NormalMove.fromUci('e2e4'));
      await _untilCoachMoved(g);
      expect(g.moves, hasLength(2));
      expect(g.chat.map((m) => m.text).join(' '), contains('centre pawn'));
      expect(g.chat.map((m) => m.text).join(' '), contains('simple rules'));
    },
  );

  test(
    'a Stockfish search failure does not freeze the game or hints',
    () async {
      final host = EngineHost(
        starter: () => ChessEngine.start(process: FailingSearchUci()),
      );
      final g = GameController(host: host)..newGame(side: Side.white, elo: 800);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await g.playerMove(NormalMove.fromUci('e2e4'));
      await _untilCoachMoved(g);
      expect(g.moves, hasLength(2));
      expect(g.thinking, isFalse);
      expect(g.position.turn, Side.white);
      expect(
        g.chat.any((message) => message.tone == CoachTone.warning),
        isTrue,
      );

      await g.hint();
      expect(g.chat.last.text, startsWith('Hint:'));
    },
  );

  test('coach moves first when the player takes Black', () async {
    final g = GameController(host: _host())
      ..newGame(side: Side.black, elo: 1200);
    await _untilCoachMoved(g);
    expect(g.moves, hasLength(1));
    expect(g.position.turn, Side.black);
  });

  test(
    'the coach voice rewords an error explanation when it is ready',
    () async {
      final asked = <String>[];
      final g = GameController(
        host: _host((pos) => pos.board.pieceAt(Square.a3) != null ? -900 : 0),
        polish: (facts) async {
          asked.add(facts);
          return 'Friendly: $facts';
        },
      )..newGame(side: Side.white, elo: 800);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final reply = g.playerMove(NormalMove.fromUci('a2a3'));
      for (var i = 0; i < 40 && asked.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(asked, hasLength(1));
      expect(
        g.chat.any((m) => m.text == 'Blunder. Friendly: ${asked.single}'),
        isTrue,
      );
      await reply;
    },
  );

  test('flags a blunder and shows the better move', () async {
    // Every position is equal except the one after 1.e4 e5 2.Qh5 Nc6 3.Qxe5+?? style
    // drop: here, any position after White plays a2a3 is scored as lost.
    final g = GameController(
      host: _host((pos) => pos.board.pieceAt(Square.a3) != null ? -900 : 0),
    )..newGame(side: Side.white, elo: 800);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final reply = g.playerMove(NormalMove.fromUci('a2a3'));
    for (var i = 0; i < 40 && g.grades[0] == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(g.grades[0], MoveQuality.blunder);
    expect(
      g.chat.any(
        (m) => m.tone == CoachTone.error && m.text.startsWith('Blunder'),
      ),
      isTrue,
    );
    // The better move stays on the board until the coach replies.
    expect(g.arrow, isNotNull);
    await reply;
    expect(g.arrow, isNull);
  });

  test('hint first highlights the piece, then shows the move', () async {
    final g = GameController(host: _host())
      ..newGame(side: Side.white, elo: 800);
    await g.hint();
    expect(g.highlight, isNotNull);
    expect(g.arrow, isNull);
    await g.hint();
    expect(g.arrow, isNotNull);
  });

  test('undo takes back the player move and the reply', () async {
    final g = GameController(host: _host())
      ..newGame(side: Side.white, elo: 800);
    await g.playerMove(NormalMove.fromUci('e2e4'));
    await _untilCoachMoved(g);
    expect(g.moves, hasLength(2));
    g.undo();
    expect(g.moves, isEmpty);
    expect(g.canUndo, isFalse);
  });

  test('saves and restores an unfinished game', () async {
    String? saved;
    final g = GameController(host: _offline, onSave: (j) => saved = j)
      ..newGame(side: Side.white, elo: 1000);
    await g.playerMove(NormalMove.fromUci('d2d4'));
    await _untilCoachMoved(g);
    expect(jsonDecode(saved!)['moves'], hasLength(2));

    final restored = GameController(host: _offline);
    expect(restored.restore(saved!), isTrue);
    expect(restored.moves.map((m) => m.uci), g.moves.map((m) => m.uci));
    expect(restored.coachElo, 1000);
    expect(restored.restore('{"moves":["e2e5"]}'), isFalse);
    expect(restored.restore(jsonEncode({'elo': 99999, 'moves': []})), isTrue);
    expect(restored.coachElo, 3200);
    expect(
      restored.restore(
        jsonEncode({'moves': List<String>.filled(1001, 'e2e4')}),
      ),
      isFalse,
    );
  });

  test('resigning ends the game and clears the save', () async {
    String? saved = 'x';
    final g = GameController(host: _offline, onSave: (j) => saved = j)
      ..newGame(side: Side.white, elo: 800);
    await g.playerMove(NormalMove.fromUci('e2e4'));
    await _untilCoachMoved(g);
    g.resign();
    expect(g.isOver, isTrue);
    expect(saved, isNull);
  });

  group('two players', () {
    test('a new casual game cannot expose the previous coach review', () async {
      final archived = <GameRecord>[];
      final g = GameController(host: _offline, onFinished: archived.add)
        ..lastRecord = GameRecord(
          id: 'previous',
          date: DateTime.utc(2026),
          playerSide: Side.white,
          coachElo: 800,
          moves: ['e2e4', 'e7e5'],
          result: '1-0',
          ending: 'checkmate',
        );

      g.newGame(side: Side.white, elo: 800, twoPlayers: true);
      expect(g.lastRecord, isNull);
      await g.playerMove(NormalMove.fromUci('e2e4'));
      g.resign();

      expect(g.lastRecord, isNull);
      expect(archived, isEmpty);
    });

    test(
      'both sides are human, the coach never moves, and hints name the side',
      () async {
        final g = GameController(host: _host())
          ..newGame(side: Side.white, elo: 800, twoPlayers: true);
        expect(g.twoPlayers, isTrue);
        await g.playerMove(NormalMove.fromUci('e2e4'));
        expect(
          g.moves,
          hasLength(1),
          reason: 'no coach reply in a two-player game',
        );
        expect(g.playerToMove, isTrue, reason: 'Black is also human');
        await g.playerMove(NormalMove.fromUci('e7e5'));
        expect(g.moves, hasLength(2));
        await g.hint();
        expect(g.chat.map((m) => m.text).join(' '), contains('White'));
        expect(g.lastRecord, isNull);
      },
    );

    test(
      'checkmate ends the two-player game and rejects further moves',
      () async {
        final g = GameController(host: _offline)
          ..newGame(side: Side.white, elo: 800, twoPlayers: true);

        for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
          await g.playerMove(NormalMove.fromUci(uci));
        }

        expect(g.isOver, isTrue);
        expect(g.position.isCheckmate, isTrue);
        expect(g.chat.last.text, 'Checkmate! Black wins.');
        expect(g.lastRecord, isNull);
        await g.playerMove(NormalMove.fromUci('a2a3'));
        expect(g.moves, hasLength(4));
      },
    );

    test(
      'undo takes back exactly one move and resigning names the winner',
      () async {
        final g = GameController(host: _offline)
          ..newGame(side: Side.white, elo: 800, twoPlayers: true);
        await g.playerMove(NormalMove.fromUci('e2e4'));
        await g.playerMove(NormalMove.fromUci('e7e5'));
        g.undo();
        expect(
          g.moves,
          hasLength(1),
          reason: 'one ply back, not a whole round',
        );
        expect(g.position.turn, Side.black);
        g.resign();
        expect(g.isOver, isTrue);
        expect(g.chat.last.text, contains('Black resigned. White wins.'));
        expect(
          g.lastRecord,
          isNull,
          reason: 'two-player games are not archived',
        );
      },
    );

    test('an unfinished two-player game survives save and restore', () async {
      String? saved;
      final g = GameController(host: _offline, onSave: (j) => saved = j)
        ..newGame(side: Side.white, elo: 800, twoPlayers: true);
      await g.playerMove(NormalMove.fromUci('d2d4'));
      expect(saved, contains('"two":true'));

      final restored = GameController(host: _offline);
      expect(restored.restore(saved!), isTrue);
      expect(restored.twoPlayers, isTrue);
      expect(restored.moves.map((m) => m.uci), ['d2d4']);
      expect(
        restored.playerToMove,
        isTrue,
        reason: 'Black to move, still human',
      );
    });

    test(
      'undo takes back first move even if playerSide was Black in two-player mode',
      () async {
        final g = GameController(host: _offline)
          ..newGame(side: Side.black, elo: 800, twoPlayers: true);
        expect(g.canUndo, isFalse);
        await g.playerMove(NormalMove.fromUci('e2e4'));
        expect(g.canUndo, isTrue);
        g.undo();
        expect(g.moves, isEmpty);
        expect(g.position.turn, Side.white);
      },
    );

    test(
      'threefold repetition is detected and ends game in draw with announcement',
      () async {
        final g = GameController(host: _offline)
          ..newGame(side: Side.white, elo: 800, twoPlayers: true);

        final repetitionMoves = [
          'g1f3',
          'g8f6',
          'f3g1',
          'f6g8',
          'g1f3',
          'g8f6',
          'f3g1',
          'f6g8',
        ];
        for (final m in repetitionMoves) {
          expect(g.isOver, isFalse);
          await g.playerMove(NormalMove.fromUci(m));
        }

        expect(g.isThreefoldRepetition, isTrue);
        expect(g.isOver, isTrue);
        expect(g.chat.last.text, 'Threefold repetition: the game is a draw.');
      },
    );

    test('undo does not crash when positions has fewer than 2 elements', () {
      final g = GameController(host: _offline)
        ..newGame(side: Side.white, elo: 800);
      expect(() => g.undo(), returnsNormally);
    });

    test('disposing controller safely ignores subsequent notifications', () {
      final g = GameController(host: _offline)
        ..newGame(side: Side.white, elo: 800);
      g.dispose();
      expect(() => g.notifyListeners(), returnsNormally);
    });
  });
}
