import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<void> openSection(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Home keeps playing and learning visible, with details on demand',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChessCoachApp(
          settings: AppSettings.memory(),
          store: EventStore.memory(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Play the coach').hitTestable(), findsOneWidget);
      expect(find.text('Puzzle break').hitTestable(), findsOneWidget);
      expect(find.text('Opening principles').hitTestable(), findsOneWidget);
      expect(find.text('Estimated rating'), findsNothing);
      expect(find.text('How much time do you have?'), findsNothing);
      await openSection(tester, 'Training options');
      for (final time in ['2 min', '15 min', '1 hour', '2 h+']) {
        expect(find.text(time), findsOneWidget);
      }
      await openSection(tester, 'Training options');
      expect(find.text('15 min'), findsNothing);
      await openSection(tester, 'Your progress');
      expect(find.text('Estimated rating'), findsOneWidget);
      expect(find.text('Your skills'), findsOneWidget);
      expect(find.text('Recent games'), findsOneWidget);
    },
  );

  testWidgets('Home stays usable with large text and narrow desktop windows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = await storeWithReviewedGame();
    for (final size in [
      const Size(240, 380),
      const Size(320, 480),
      const Size(700, 320),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ChessCoachApp(
          key: UniqueKey(),
          settings: AppSettings.memory(),
          store: store,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Home $size');
      for (final title in ['Training options', 'Your progress']) {
        await openSection(tester, title);
        expect(tester.takeException(), isNull, reason: '$title $size');
      }
      await tester.ensureVisible(find.text('Review').first);
      await tester.pumpAndSettle();
      expect(find.text('Review').first.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Recent games $size');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
    }
  });
}
