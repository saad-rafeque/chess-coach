import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<void> _pumpAt(WidgetTester tester, Size size, AppSettings settings, {EventStore? store}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChessCoachApp(settings: settings, store: store ?? EventStore.memory()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop layout shows side navigation and switches theme', (tester) async {
    final settings = AppSettings.memory();
    await _pumpAt(tester, const Size(1400, 900), settings);

    expect(find.text('Chess Coach'), findsOneWidget);
    expect(find.text('How much time do you have?'), findsOneWidget);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wooden'));
    await tester.pumpAndSettle();
    expect(settings.theme, AppTheme.wooden);
  });

  testWidgets('phone layout shows bottom navigation', (tester) async {
    await _pumpAt(tester, const Size(390, 844), AppSettings.memory());

    expect(find.text('Chess Coach'), findsNothing);
    for (final label in ['Home', 'Play', 'Puzzles', 'Lessons', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('Play').last);
    await tester.pumpAndSettle();
    expect(find.text('Training'), findsOneWidget);

    // Every page must lay out without overflow on a phone.
    for (final label in ['Puzzles', 'Lessons', 'Settings', 'Home']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('short desktop window lays out every page', (tester) async {
    await _pumpAt(tester, const Size(1250, 620), AppSettings.memory());
    for (final label in ['Play', 'Puzzles', 'Lessons', 'Settings', 'Home']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('recent game opens a full review', (tester) async {
    await _pumpAt(tester, const Size(1400, 900), AppSettings.memory(), store: await storeWithReviewedGame());
    expect(find.text('Recent games'), findsOneWidget);
    await tester.ensureVisible(find.text('Review').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review').first);
    await tester.pumpAndSettle();
    expect(find.text('Game review'), findsOneWidget);
    expect(find.text('Your accuracy'), findsOneWidget);
    expect(find.textContaining('Move 3: Nf6'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('Move 3: Nf6'));
    await tester.tap(find.textContaining('Move 3: Nf6'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Show the better move'));
    await tester.tap(find.text('Show the better move'));
    await tester.pumpAndSettle();
    expect(find.text('Back to the game'), findsOneWidget);
  });
}
