import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/main.dart';
import 'package:chess_coach/data/curriculum.dart';
import 'package:chess_coach/puzzles/puzzle.dart';
import 'package:chess_coach/screens/home_page.dart';
import 'package:chess_coach/screens/puzzles_page.dart';
import 'package:chess_coach/screens/session_page.dart';
import 'package:chess_coach/train/planner.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<void> _pump(
  WidgetTester tester,
  EventStore store, {
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => TrainingSession.current.value = null);
  await tester.pumpWidget(
    ChessCoachApp(settings: AppSettings.memory(), store: store),
  );
  await tester.pumpAndSettle();
}

void main() {
  const block = Activity(
    kind: ActivityKind.puzzles,
    minutes: 3,
    title: 'Three puzzles',
    detail: 'Practice',
    area: Area.tactics,
    features: [1, 0, 0, 0, 0],
    count: 3,
  );
  Future<void> attempt(EventStore store, String id) =>
      store.add(puzzleEventType, {
        'id': id,
        'solved': true,
        'puzzleRating': 900,
        'rated': true,
        'themes': ['fork'],
      });

  test(
    'resuming preserves partial work and records completion only once',
    () async {
      final store = EventStore.memory();
      final session = TrainingSession(3, [block]);
      session.begin(0, store);
      await attempt(store, 'one');
      await attempt(store, 'two');
      expect(session.refresh(store), isFalse);
      session.begin(0, store);
      expect(session.remaining(0, store), 1);
      await attempt(store, 'three');
      expect(session.refresh(store), isTrue);
      expect(session.finished, isTrue);
      expect(session.refresh(store), isFalse);
      expect(store.ofType(activityEventType), hasLength(1));
    },
  );

  test(
    'old synced attempts cannot complete a current training block',
    () async {
      final store = EventStore.memory();
      await attempt(store, 'before');
      final session = TrainingSession(3, [block]);
      session.begin(0, store);
      await attempt(store, 'one');
      await store.merge([
        for (var i = 0; i < 3; i++)
          AppEvent(
            id: 'old-$i',
            type: puzzleEventType,
            time: DateTime.utc(2020),
            device: 'other',
            data: {
              'id': 'old-$i',
              'solved': true,
              'puzzleRating': 900,
              'rated': true,
            },
          ),
      ]);
      expect(session.remaining(0, store), 2);
      expect(session.refresh(store), isFalse);
    },
  );

  testWidgets('Continue opens only the remaining puzzles in a block', (
    tester,
  ) async {
    final store = EventStore.memory();
    await _pump(tester, store);
    final session = TrainingSession(3, [block]);
    TrainingSession.current.value = session;
    session.begin(0, store);
    await attempt(store, 'one');
    await attempt(store, 'two');
    // ignore: unawaited_futures
    openSession(tester.element(find.byType(HomePage)), onNavigate: (_) {});
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(tester.widget<PuzzlesPage>(find.byType(PuzzlesPage)).goal, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a time tile plans a session that can be resumed from Home', (
    tester,
  ) async {
    await _pump(tester, EventStore.memory());
    expect(find.text('Preview data'), findsNothing);
    expect(
      find.text('New'),
      findsOneWidget,
      reason: 'no rating before any training',
    );

    await tester.tap(find.text('15 min'));
    await tester.pumpAndSettle();
    expect(find.text('15-minute session'), findsOneWidget);
    expect(find.text('Warm-up: 3 puzzles'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^0 of \d done$')), findsOneWidget);

    // Skipping a block counts it as done.
    await tester.tap(find.byIcon(FluentIcons.cancel).first);
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^1 of \d done$')), findsOneWidget);

    await tester.tap(find.byIcon(FluentIcons.back));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your 15-minute session: 1 of'), findsOneWidget);
  });

  testWidgets('review opens the due cards', (tester) async {
    await _pump(
      tester,
      await storeWithReviewedGame(),
      size: const Size(390, 844),
    );
    await tester.ensureVisible(find.textContaining('to review'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('to review'));
    await tester.pumpAndSettle();
    expect(find.text('Your mistake'), findsOneWidget);
    await tester.tap(find.text('Show answer'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('You will see this one again soon.'), findsOneWidget);
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('Review finished'), findsOneWidget);
  });
}
