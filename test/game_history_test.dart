import 'dart:convert';

import 'package:chess_coach/data/game_record.dart';
import 'package:chess_coach/engine/engine_host.dart';
import 'package:chess_coach/engine/chess_engine.dart';
import 'package:chess_coach/game/game_controller.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

import 'game_controller_test.dart' show PendingAnalysisEngine, ScriptedEngine;

EngineHost _offline() =>
    EngineHost(starter: () => Future.error(UnsupportedError('offline test')));

void main() {
  test(
    'optional coach wording failure preserves feedback and the reply',
    () async {
      final host = EngineHost(
        starter: () => ChessEngine.start(
          process: ScriptedEngine(
            (position) => position.board.pieceAt(Square.a3) != null ? -900 : 0,
          ),
        ),
      );
      var polishCalls = 0;
      final g = GameController(
        host: host,
        polish: (_) {
          polishCalls++;
          return Future.error(StateError('model was unloaded'));
        },
      )..newGame(side: Side.white, elo: 800);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await g.playerMove(NormalMove.fromUci('a2a3'));
      expect(polishCalls, 1);
      expect(
        g.chat.any((message) => message.text.startsWith('Blunder.')),
        isTrue,
      );
      expect(g.moves, hasLength(2));
      expect(g.thinking, isFalse);
      g.dispose();
      await host.dispose();
    },
  );

  test('feedback arrows cannot be played as a hint', () async {
    final host = _offline();
    final g = GameController(host: host)
      ..newGame(side: Side.white, elo: 800, twoPlayers: true)
      ..arrow = NormalMove.fromUci('e2e4');
    expect(g.canPlayHint, isFalse);
    await g.playHint();
    expect(g.moves, isEmpty);
    g.dispose();
    await host.dispose();
  });

  for (final side in Side.values) {
    test('redo restores the complete coach turn for $side', () async {
      final host = EngineHost(
        starter: () => ChessEngine.start(process: ScriptedEngine()),
      );
      final g = GameController(host: host)
        ..setMode(PlayMode.real)
        ..newGame(side: side, elo: 800);
      if (side == Side.black) {
        for (var i = 0; i < 30 && g.thinking; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      await g.playerMove(
        NormalMove.fromUci(side == Side.white ? 'e2e4' : 'e7e5'),
      );
      final fen = g.position.fen;
      final moves = g.moves.map((m) => m.uci).toList();
      g.undo();
      expect(g.moves.length, moves.length - 2);
      expect(g.canRedo, isTrue);
      expect(g.evaluation, isNull);
      g.redo();
      expect(g.position.fen, fen);
      expect(g.moves.map((m) => m.uci), moves);
      expect(g.canRedo, isFalse);
      expect(g.thinking, isFalse);
      g.dispose();
      await host.dispose();
    });
  }

  test(
    'two-player history redoes one ply and invalidates a divergent branch',
    () async {
      final host = _offline();
      final g = GameController(host: host)
        ..newGame(side: Side.white, elo: 800, twoPlayers: true);
      for (final move in ['e2e4', 'e7e5', 'g1f3']) {
        await g.playerMove(NormalMove.fromUci(move));
      }
      g.undo();
      g.undo();
      expect(g.moves.map((m) => m.uci), ['e2e4']);
      g.redo();
      expect(g.moves.map((m) => m.uci), ['e2e4', 'e7e5']);
      expect(g.canRedo, isTrue);
      await g.playerMove(NormalMove.fromUci('b1c3'));
      expect(g.canRedo, isFalse);
      final fen = g.position.fen;
      g.redo();
      expect(g.position.fen, fen);
      g.dispose();
      await host.dispose();
    },
  );

  test('new game and restore discard redo history', () async {
    final host = _offline();
    final g = GameController(host: host)
      ..newGame(side: Side.white, elo: 800, twoPlayers: true);
    await g.playerMove(NormalMove.fromUci('e2e4'));
    g.undo();
    expect(g.canRedo, isTrue);
    g.newGame(side: Side.white, elo: 800, twoPlayers: true);
    expect(g.canRedo, isFalse);
    await g.playerMove(NormalMove.fromUci('d2d4'));
    g.undo();
    expect(g.canRedo, isTrue);
    expect(
      g.restore(
        jsonEncode({
          'two': true,
          'moves': ['c2c4'],
        }),
      ),
      isTrue,
    );
    expect(g.canRedo, isFalse);
    g.dispose();
    await host.dispose();
  });

  test(
    'redo during a cancelled coach search produces exactly one reply',
    () async {
      final engine = PendingAnalysisEngine();
      final host = EngineHost(starter: () async => engine);
      final g = GameController(host: host)..setMode(PlayMode.real);
      final original = g.playerMove(NormalMove.fromUci('e2e4'));
      await Future<void>.delayed(Duration.zero);
      expect(engine.requests, hasLength(1));
      g.undo();
      g.redo();
      expect(g.thinking, isTrue);
      expect(g.canRedo, isFalse);
      await Future<void>.delayed(Duration.zero);
      // Undo's background evaluation is cancelled before it starts; only the
      // old coach request and the replacement coach request remain.
      expect(engine.requests, hasLength(2));
      engine.finish(0);
      engine.finish(1);
      await original;
      for (var i = 0; i < 30 && g.thinking; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(g.moves, hasLength(2));
      expect(g.moves.first.uci, 'e2e4');
      expect(g.position.turn, Side.white);
      expect(g.thinking, isFalse);
      g.dispose();
      await host.dispose();
    },
  );

  test(
    'redo of a checkmating move preserves the record without archiving twice',
    () async {
      final host = _offline();
      final archived = <GameRecord>[];
      final g = GameController(host: host, onFinished: archived.add);
      expect(
        g.restore(
          jsonEncode({
            'side': 'black',
            'mode': 'real',
            'moves': ['f2f3', 'e7e5', 'g2g4'],
          }),
        ),
        isTrue,
      );
      await g.playerMove(NormalMove.fromUci('d8h4'));
      expect(g.isOver, isTrue);
      expect(archived, hasLength(1));
      final record = g.lastRecord;
      g.undo();
      expect(g.isOver, isFalse);
      expect(g.lastRecord, isNull);
      g.redo();
      expect(g.position.isCheckmate, isTrue);
      expect(g.lastRecord, same(record));
      expect(archived, hasLength(1));
      g.dispose();
      await host.dispose();
    },
  );

  test(
    'offline hints reveal a legal piece and then the same suggested move',
    () async {
      final host = _offline();
      final g = GameController(host: host)
        ..newGame(side: Side.white, elo: 800, twoPlayers: true);
      final states = <bool>[];
      g.addListener(() => states.add(g.hintThinking));
      await g.hint();
      final pieceSquare = g.highlight;
      expect(pieceSquare, isNotNull);
      expect(g.canPlayHint, isFalse);
      await g.playHint();
      expect(g.moves, isEmpty);
      await g.hint();
      final move = g.arrow!;
      expect(move.from, pieceSquare);
      expect(g.position.isLegal(move), isTrue);
      expect(g.canPlayHint, isTrue);
      expect(states, contains(true));
      expect(states.last, isFalse);
      await g.playHint();
      expect(g.moves.single, move);
      expect(g.canPlayHint, isFalse);
      expect(g.hintThinking, isFalse);
      await g.playHint();
      expect(g.moves, hasLength(1));
      g.dispose();
      await host.dispose();
    },
  );

  for (final action in ['undo', 'redo', 'move', 'new game', 'real mode']) {
    test('a revealed hint is invalidated by $action', () async {
      final engine = PendingAnalysisEngine();
      final host = EngineHost(starter: () async => engine);
      final g = GameController(host: host)
        ..newGame(side: Side.white, elo: 800, twoPlayers: true);
      await g.playerMove(NormalMove.fromUci('e2e4'));
      if (action == 'redo') g.undo();
      final hint = g.hint();
      await Future<void>.delayed(Duration.zero);
      engine.finish(0);
      await hint;
      await g.hint();
      expect(g.canPlayHint, isTrue);
      switch (action) {
        case 'undo':
          g.undo();
        case 'redo':
          g.redo();
        case 'move':
          await g.playerMove(NormalMove.fromUci('e7e5'));
        case 'new game':
          g.newGame(side: Side.white, elo: 800, twoPlayers: true);
        case 'real mode':
          // Even though two-player mode still permits fresh hints, switching
          // mode must invalidate the suggestion from before that switch.
          g.setMode(PlayMode.real);
      }
      expect(g.canPlayHint, isFalse);
      final count = g.moves.length;
      await g.playHint();
      expect(g.moves, hasLength(count));
      g.dispose();
      await host.dispose();
    });
  }

  test('pending hint cannot overwrite a redone position', () async {
    final engine = PendingAnalysisEngine();
    final host = EngineHost(starter: () async => engine);
    final g = GameController(host: host)
      ..newGame(side: Side.white, elo: 800, twoPlayers: true);
    await g.playerMove(NormalMove.fromUci('e2e4'));
    g.undo();
    final hint = g.hint();
    await Future<void>.delayed(Duration.zero);
    g.redo();
    engine.finish(0);
    await hint;
    expect(g.highlight, isNull);
    expect(g.arrow, isNull);
    expect(g.canPlayHint, isFalse);
    expect(g.hintThinking, isFalse);
    g.dispose();
    await host.dispose();
  });
}
