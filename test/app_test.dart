import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/main.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentIcons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  AppSettings settings, {
  EventStore? store,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChessCoachApp(settings: settings, store: store ?? EventStore.memory()),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop layout shows side navigation and switches theme', (
    tester,
  ) async {
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
    final settings = AppSettings.memory();
    expect(settings.panelUnderBoard, isFalse);
    await _pumpAt(tester, const Size(390, 844), settings);

    expect(find.text('Chess Coach'), findsNothing);
    for (final label in ['Home', 'Play', 'Puzzles', 'Lessons', 'Settings']) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.text('Play').last);
    await tester.pumpAndSettle();
    expect(find.text('Training'), findsOneWidget);
    expect(find.textContaining('New game!').hitTestable(), findsOneWidget);

    // Every page must lay out without overflow on a phone.
    for (final label in ['Puzzles', 'Lessons', 'Settings', 'Home']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'short split-screen and PiP windows keep the board and coach controls visible',
    (tester) async {
      void checkStep(String step) {
        final error = tester.takeException();
        expect(error, isNull, reason: '$step: $error');
      }

      await _pumpAt(tester, const Size(390, 844), AppSettings.memory());
      checkStep('initial phone screen');
      await tester.tap(find.text('Play').last);
      await tester.pumpAndSettle();
      checkStep('open Play');

      await tester.tap(find.text('New').last);
      await tester.pumpAndSettle();
      checkStep('open New game');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      checkStep('close New game');

      tester.view.physicalSize = const Size(320, 700);
      tester.binding.handleMetricsChanged();
      await tester.pumpAndSettle();
      checkStep('resize phone');
      await tester.tap(find.text('New').last);
      await tester.pumpAndSettle();
      checkStep('open New game on narrow phone');
      await tester.tap(find.text('Two players'));
      await tester.pumpAndSettle();
      checkStep('select two players');
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      checkStep('start two-player game');

      for (final size in [const Size(390, 380), const Size(320, 180)]) {
        tester.view.physicalSize = size;
        tester.binding.handleMetricsChanged();
        await tester.pumpAndSettle();
        final layoutError = tester.takeException();
        final details = layoutError is FlutterError
            ? layoutError.diagnostics.map((d) => d.toStringDeep()).join('\n')
            : '$layoutError';
        expect(layoutError, isNull, reason: 'window size $size\n$details');
        expect(find.byKey(const ValueKey('play-board')), findsOneWidget);
        expect(
          tester.getSize(find.byKey(const ValueKey('play-board'))).width,
          greaterThan(size.height < 200 ? 90 : 250),
        );
        expect(find.text('Coach'), findsWidgets);
        expect(find.text('Hint'), findsOneWidget);
        if (size.height < 200) {
          expect(
            find.textContaining('White to move').hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.text('Coach').last);
          await tester.pumpAndSettle();
          checkStep('open Coach suggestions in PiP-sized window');
          expect(find.textContaining('suggestion'), findsOneWidget);
        }
      }
    },
  );

  testWidgets('short desktop window lays out every page', (tester) async {
    await _pumpAt(tester, const Size(1250, 620), AppSettings.memory());
    for (final label in ['Play', 'Puzzles', 'Lessons', 'Settings', 'Home']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('recent game opens a full review', (tester) async {
    await _pumpAt(
      tester,
      const Size(1400, 900),
      AppSettings.memory(),
      store: await storeWithReviewedGame(),
    );
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

  testWidgets(
    'large text: every screen lays out on a phone at 150% font size',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpAt(
        tester,
        const Size(390, 844),
        AppSettings.memory(),
        store: await storeWithReviewedGame(),
      );
      for (final label in ['Play', 'Puzzles', 'Lessons', 'Settings', 'Home']) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }
      // Pushed pages: a lesson, a session, the review cards and a game review.
      await tester.tap(find.text('Lessons').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opening principles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FluentIcons.back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FluentIcons.back));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('to review'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('to review'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(FluentIcons.back));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review').first);
      await tester.pumpAndSettle();
      expect(find.text('Game review'), findsOneWidget);
    },
  );
}
