import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/main.dart';
import 'package:chess_coach/screens/session_page.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<void> _pump(WidgetTester tester, EventStore store, {Size size = const Size(1400, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() => TrainingSession.current.value = null);
  await tester.pumpWidget(ChessCoachApp(settings: AppSettings.memory(), store: store));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a time tile plans a session that can be resumed from Home', (tester) async {
    await _pump(tester, EventStore.memory());
    expect(find.text('Preview data'), findsNothing);
    expect(find.text('New'), findsOneWidget, reason: 'no rating before any training');

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
    await _pump(tester, await storeWithReviewedGame(), size: const Size(390, 844));
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
