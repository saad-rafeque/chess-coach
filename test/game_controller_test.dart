import 'dart:async';
import 'dart:convert';

import 'package:chess_coach/coach/coach_player.dart';
import 'package:chess_coach/engine/chess_engine.dart';
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

    test('undo takes back first move even if playerSide was Black in two-player mode', () async {
      final g = GameController(host: _offline)
        ..newGame(side: Side.black, elo: 800, twoPlayers: true);
      expect(g.canUndo, isFalse);
      await g.playerMove(NormalMove.fromUci('e2e4'));
      expect(g.canUndo, isTrue);
      g.undo();
      expect(g.moves, isEmpty);
      expect(g.position.turn, Side.white);
    });
  });
}
