import 'package:chess_coach/data/curriculum.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/data/game_record.dart';
import 'package:chess_coach/lessons/progress.dart';
import 'package:chess_coach/puzzles/puzzle.dart';
import 'package:chess_coach/train/cards.dart';
import 'package:chess_coach/train/fsrs.dart';
import 'package:chess_coach/train/planner.dart';
import 'package:chess_coach/train/skill_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

AppEvent _event(String type, Map<String, dynamic> data, DateTime time, [String? id]) =>
    AppEvent(id: id ?? newId(), type: type, time: time, device: 'test', data: data);

Map<String, dynamic> _puzzle(bool solved, {int rating = 900, List<String> themes = const ['fork', 'middlegame']}) =>
    {'id': newId(), 'solved': solved, 'puzzleRating': rating, 'themes': themes, 'rated': true};

void main() {
  group('FSRS', () {
    const fsrs = Fsrs();
    final t0 = DateTime.utc(2026, 1, 1, 12);

    test('a new card graded good comes back in a few days', () {
      final c = fsrs.review(null, Grade.good, t0);
      expect(c.stability, closeTo(Fsrs.w[2], 1e-9));
      expect(c.due.difference(t0).inDays, inInclusiveRange(3, 5));
      expect(c.reps, 1);
    });

    test('again brings it back in minutes and counts a lapse', () {
      final c1 = fsrs.review(null, Grade.good, t0);
      final c2 = fsrs.review(c1, Grade.again, c1.due);
      expect(c2.due.difference(c1.due), const Duration(minutes: 10));
      expect(c2.lapses, 1);
      expect(c2.stability, lessThan(c1.stability));
    });

    test('successful reviews grow the interval, easy more than hard', () {
      final c1 = fsrs.review(null, Grade.good, t0);
      final good = fsrs.review(c1, Grade.good, c1.due);
      final hard = fsrs.review(c1, Grade.hard, c1.due);
      final easy = fsrs.review(c1, Grade.easy, c1.due);
      expect(good.stability, greaterThan(c1.stability));
      expect(easy.stability, greaterThan(good.stability));
      expect(hard.stability, lessThan(good.stability));
      expect(good.difficulty, lessThanOrEqualTo(hard.difficulty));
    });

    test('recall probability is 90% after one stability', () {
      expect(Fsrs.retrievability(10, 10), closeTo(0.9, 1e-9));
      expect(Fsrs.retrievability(0, 10), 1);
    });
  });

  group('skill model', () {
    test('knows nothing without events', () {
      final m = SkillModel.fromEvents(const []);
      expect(m.hasData, isFalse);
      expect(m.estimatedRating, isNull);
      expect(Area.all.where(m.rated), isEmpty);
      expect(m.recommendedCoachElo, 750);
    });

    test('puzzles rate tactics, phases and themes', () {
      final now = DateTime.now();
      final events = [
        for (var i = 0; i < 12; i++) _event(puzzleEventType, _puzzle(i % 3 != 0, rating: 1000), now),
        for (var i = 0; i < 6; i++) _event(puzzleEventType, _puzzle(false, rating: 700, themes: ['pin', 'endgame']), now),
      ];
      final m = SkillModel.fromEvents(events);
      expect(m.rated(Area.tactics), isTrue);
      expect(m.rated(Area.middlegame), isTrue);
      expect(m.areas[Area.endgames]!.rating, lessThan(m.areas[Area.middlegame]!.rating));
      expect(m.weakestTheme, 'pin');
      expect(m.estimatedRating, isNotNull);
      expect(m.activeToday, isTrue);
      expect(m.streakDays, 1);
    });

    test('lesson exercises rate their area', () {
      final lesson = allLessons.firstWhere((l) => l.area == Area.endgames);
      final events = [
        for (var i = 0; i < 8; i++) _event(lessonEventType, lessonStepData(lesson, i, solved: true), DateTime.now()),
      ];
      final m = SkillModel.fromEvents(events);
      expect(m.rated(Area.endgames), isTrue);
      expect(m.areas[Area.endgames]!.rating, greaterThan(900));
    });

    test('games set the playing rating and the recommended coach strength', () {
      final now = DateTime.now();
      final events = [
        for (var i = 0; i < 10; i++)
          _event(GameRecord.eventType,
              {'side': 'white', 'elo': 800, 'moves': <String>[], 'result': i < 3 ? '1-0' : '0-1', 'ending': 'resign'}, now),
      ];
      final m = SkillModel.fromEvents(events);
      expect(m.gamesPlayed, 10);
      expect(m.games.rating, lessThan(800), reason: 'won only 3 of 10 against 800');
      // A little above the player's strength: about a 45% expected score.
      expect(m.recommendedCoachElo, inInclusiveRange(m.games.rating.round(), m.games.rating.round() + 100));
    });

    test('a reviewed game rates the opening phase', () async {
      final store = await storeWithReviewedGame();
      final m = SkillModel.fromEvents(store.events);
      expect(m.areas[Area.openings]!.deviation, lessThan(350));
      expect(m.areas[Area.openings]!.rating, lessThan(900), reason: 'the game had a blunder in the opening');
    });

    test('streak counts consecutive training days', () {
      final today = DateTime(2026, 3, 10, 12);
      final events = [
        for (final d in [7, 8, 9]) _event(puzzleEventType, _puzzle(true), DateTime(2026, 3, d, 12).toUtc()),
      ];
      final m = SkillModel.fromEvents(events, now: today);
      expect(m.streakDays, 3);
      expect(m.activeToday, isFalse);
      expect(SkillModel.fromEvents(events, now: DateTime(2026, 3, 12)).streakDays, 0);
    });
  });

  group('cards', () {
    test('lesson repertoire moves and game mistakes become cards', () async {
      final store = await storeWithReviewedGame();
      final opening = allLessons.firstWhere((l) => l.area == Area.openings);
      await store.add(lessonEventType, lessonStepData(opening, 1, solved: true));
      final deck = CardDeck.fromStore(store);
      expect(deck.cards.map((c) => c.kind).toSet(), {CardKind.opening, CardKind.mistake});
      final due = deck.due();
      expect(due.first.kind, CardKind.mistake, reason: 'your own mistakes first');
      expect(due.length, deck.cards.length);

      await store.add(cardEventType, cardReviewData(due.first, Grade.good));
      final after = CardDeck.fromStore(store);
      expect(after.states[due.first.id], isNotNull);
      expect(after.due().map((c) => c.id), isNot(contains(due.first.id)));
    });

    test('new cards are limited per day', () async {
      final store = EventStore.memory();
      for (final l in allLessons.where((l) => l.area == Area.openings)) {
        for (var i = 0; i < l.steps.length; i++) {
          await store.add(lessonEventType, lessonStepData(l, i, solved: true));
        }
      }
      final deck = CardDeck.fromStore(store);
      expect(deck.cards.length, greaterThan(CardDeck.newPerDay));
      expect(deck.due().length, CardDeck.newPerDay);
    });
  });

  group('planner', () {
    Planner planner(List<AppEvent> events, {int due = 0}) => Planner(
        skills: SkillModel.fromEvents(events),
        lessons: LessonProgress.fromEvents(events),
        dueCards: due,
        events: events);

    int total(List<Activity> plan) => plan.fold(0, (s, a) => s + a.minutes);

    test('fills the time it is given', () {
      final p = planner(const []);
      final two = p.plan(2);
      expect(two.length, 1);
      expect(total(two), lessThanOrEqualTo(2));

      final fifteen = p.plan(15);
      expect(fifteen.first.title, startsWith('Warm-up'));
      expect(total(fifteen), inInclusiveRange(10, 15));

      final hour = p.plan(60);
      expect(hour.where((a) => a.kind == ActivityKind.game).length, 1);
      expect(total(hour), inInclusiveRange(45, 60));

      final long = p.plan(120);
      expect(long.where((a) => a.kind == ActivityKind.game).length, 2);
      expect(long.any((a) => a.kind == ActivityKind.lesson), isTrue);
    });

    test('due cards get reviewed', () {
      final plan = planner(const [], due: 8).plan(15);
      expect(plan.any((a) => a.kind == ActivityKind.review), isTrue);
    });

    test('learns from rewards which training pays off', () {
      final now = DateTime.now().subtract(const Duration(days: 8));
      final base = planner(const []);
      final x = base.features(ActivityKind.endgame, 12);
      final events = [
        for (var i = 0; i < 20; i++)
          _event(activityEventType, {'kind': 'endgame', 'x': x, 'reward': 1.0}, now),
        for (var i = 0; i < 20; i++)
          _event(activityEventType, {'kind': 'lesson', 'x': base.features(ActivityKind.lesson, 12), 'reward': 0.0},
              now),
      ];
      final learned = planner(events);
      final lx = learned.features(ActivityKind.lesson, 12);
      expect(learned.score(ActivityKind.endgame, x), greaterThan(learned.score(ActivityKind.lesson, lx)));
      expect(learned.score(ActivityKind.lesson, lx), lessThan(base.score(ActivityKind.lesson, lx)));
      expect(learned.plan(15)[1].kind, ActivityKind.endgame);
    });
  });
}
