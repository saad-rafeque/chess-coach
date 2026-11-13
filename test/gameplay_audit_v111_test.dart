import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/data/game_record.dart';
import 'package:chess_coach/engine/engine_host.dart';
import 'package:chess_coach/game/game_controller.dart';
import 'package:chess_coach/puzzles/mistakes.dart';
import 'package:chess_coach/puzzles/puzzle.dart';
import 'package:chess_coach/review/game_review.dart';
import 'package:chess_coach/train/skill_model.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'invalid cached engine moves cannot become impossible study puzzles',
    () async {
      final store = EventStore.memory();
      addTearDown(store.dispose);
      final gameEvent = await store.add('game', {
        'side': 'white',
        'moves': ['e2e4'],
        'elo': 800,
      }, id: 'bad-review-game');
      final reviewEvent = AppEvent(
        id: 'bad-review',
        type: 'review',
        time: DateTime.utc(2020),
        device: 'other',
        data: {
          'game': gameEvent.id,
          'scores': [
            {'cp': 0},
            {'cp': -600},
          ],
          'best': ['e2e5', null],
        },
      );
      // A syntactically valid synced review can still contain an illegal move.
      expect(await store.merge([reviewEvent]), 1);
      final review = cachedReview(GameRecord.fromEvent(gameEvent), reviewEvent);
      expect(review.moves.single.bestUci, isNull);
      expect(review.moves.single.bestSan, isNull);
      expect(mistakePuzzles(store), isEmpty);
    },
  );

  for (final dates in [
    [
      DateTime(2026, 3, 7, 12),
      DateTime(2026, 3, 8, 12),
      DateTime(2026, 3, 9, 12),
    ],
    [
      DateTime(2026, 10, 31, 12),
      DateTime(2026, 11, 1, 12),
      DateTime(2026, 11, 2, 12),
    ],
  ]) {
    test(
      'streak follows calendar days around ${dates[1].month}/${dates[1].day}',
      () {
        final events = [
          for (final (index, day) in dates.indexed)
            AppEvent(
              id: 'day-$index',
              type: 'puzzle',
              time: day.toUtc(),
              device: 'test',
              data: {'id': 'p$index', 'solved': true, 'puzzleRating': 800},
            ),
        ];
        expect(PuzzleStats.fromEvents(events, today: dates.last).streakDays, 3);
        expect(SkillModel.fromEvents(events, now: dates.last).streakDays, 3);
        final followingDay = DateTime(
          dates.last.year,
          dates.last.month,
          dates.last.day + 1,
          12,
        );
        expect(
          PuzzleStats.fromEvents(events, today: followingDay).streakDays,
          3,
        );
        expect(SkillModel.fromEvents(events, now: followingDay).streakDays, 3);
      },
    );
  }

  test(
    'threefold ignores an en-passant target that cannot be captured',
    () async {
      final host = EngineHost(
        starter: () => Future.error(StateError('offline')),
      );
      final game = GameController(host: host)
        ..newGame(side: Side.white, elo: 800, twoPlayers: true);
      addTearDown(() async {
        game.dispose();
        await host.dispose();
      });
      for (final uci in [
        'e2e4',
        'g8f6',
        'g1f3',
        'f6g8',
        'f3g1',
        'g8f6',
        'g1f3',
        'f6g8',
        'f3g1',
      ]) {
        await game.playerMove(NormalMove.fromUci(uci));
      }
      expect(game.moves, hasLength(9));
      expect(game.isThreefoldRepetition, isTrue);
      expect(game.isOver, isTrue);
      expect(game.currentGuidance, contains('Threefold repetition'));
    },
  );

  test(
    'a legally available en-passant capture makes a position distinct',
    () async {
      final host = EngineHost(
        starter: () => Future.error(StateError('offline')),
      );
      final game = GameController(host: host)
        ..newGame(side: Side.white, elo: 800, twoPlayers: true);
      addTearDown(() async {
        game.dispose();
        await host.dispose();
      });
      for (final uci in [
        'e2e4',
        'a7a6',
        'e4e5',
        'd7d5',
        'g1f3',
        'g8f6',
        'f3g1',
        'f6g8',
        'g1f3',
        'g8f6',
        'f3g1',
        'f6g8',
      ]) {
        await game.playerMove(NormalMove.fromUci(uci));
      }
      expect(game.moves, hasLength(12));
      expect(game.isThreefoldRepetition, isFalse);
      expect(game.isOver, isFalse);
    },
  );
}
