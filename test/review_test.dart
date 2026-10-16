import 'dart:io' as io;

import 'package:chess_coach/coach/coach_player.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/data/game_record.dart';
import 'package:chess_coach/engine/analysis.dart';
import 'package:chess_coach/review/game_review.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

GameRecord _game(List<String> moves, {Side side = Side.white, String result = '*'}) => GameRecord(
      id: 'g1',
      date: DateTime(2026, 10, 16),
      playerSide: side,
      coachElo: 800,
      moves: moves,
      result: result,
      ending: 'checkmate',
    );

void main() {
  group('event store', () {
    test('adds, dedupes merged events and survives a reload', () async {
      final dir = io.Directory.systemTemp.createTempSync('chess_coach_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = io.File('${dir.path}/events.jsonl');
      final a = await EventStore.openFile(file, device: 'pc');
      final e = await a.add('game', {'x': 1});
      expect(await a.merge([e]), 0);
      final other = AppEvent(id: 'remote', type: 'game', time: DateTime.utc(2020), device: 'phone', data: const {'y': 2});
      expect(await a.merge([other]), 1);
      expect(a.events.first.id, 'remote', reason: 'events stay sorted by time');

      final b = await EventStore.openFile(file, device: 'pc');
      expect(b.events.map((e) => e.id).toSet(), {e.id, 'remote'});
    });
  });

  group('game record', () {
    test('round-trips through an event and writes PGN', () {
      final g = GameRecord(
        id: 'abc',
        date: DateTime(2026, 10, 16),
        playerSide: Side.black,
        coachElo: 1200,
        moves: const ['e2e4', 'e7e5'],
        result: '1-0',
        ending: 'resignation',
        grades: const {1: MoveQuality.mistake},
      );
      final back = GameRecord.fromEvent(
          AppEvent(id: 'abc', type: GameRecord.eventType, time: DateTime.utc(2026), device: 'd', data: g.toData()));
      expect(back.moves, g.moves);
      expect(back.playerSide, Side.black);
      expect(back.grades[1], MoveQuality.mistake);
      expect(back.playerScore, 0);
      expect(g.toPgn(), contains('1. e4 e5 1-0'));
      expect(g.toPgn(), contains('[White "Coach (1200)"]'));
    });
  });

  group('review', () {
    // 1.e4 e5 2.Qh5 Nc6 3.Bc4 Nf6?? 4.Qxf7#
    final game = _game(['e2e4', 'e7e5', 'd1h5', 'b8c6', 'f1c4', 'g8f6', 'h5f7'], side: Side.black, result: '1-0');
    final analysis = GameAnalysis(
      scores: const [Score.cp(20), Score.cp(30), Score.cp(25), Score.cp(-20), Score.cp(-10), Score.cp(0),
          Score.mate(1), Score.cp(10000)],
      best: const ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'g7g6', 'h5f7', null],
    );

    test('finds the blunder, explains it and lowers accuracy', () {
      final r = buildReview(game, analysis);
      final blunder = r.moves[5];
      expect(blunder.san, 'Nf6');
      expect(blunder.quality, MoveQuality.blunder);
      expect(blunder.bestSan, 'g6');
      expect(blunder.explanation, contains('checkmate'));
      expect(r.keyMoments().single.ply, 5);
      expect(r.count(Side.black, MoveQuality.blunder), 1);
      expect(r.accuracy(Side.black), lessThan(r.accuracy(Side.white)));
      expect(r.moves[6].quality, MoveQuality.best);
    });

    test('analysis data round-trips', () {
      final back = GameAnalysis.fromData(analysis.toData('g1'));
      expect(back.scores, analysis.scores);
      expect(back.best, analysis.best);
    });

    test('accuracy curve', () {
      expect(moveAccuracy(0), closeTo(100, 0.01));
      expect(moveAccuracy(30), lessThan(30));
    });
  });
}
