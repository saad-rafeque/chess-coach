import 'package:chess_coach/app/picture_in_picture.dart';
import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/app/theme.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/main.dart';
import 'package:chess_coach/widgets/board_layout.dart';
import 'package:chessground/chessground.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('captured pieces fit a 40px player bar', (tester) async {
    for (final scale in [1.0, 1.15, 1.5, 2.0]) {
      await tester.pumpWidget(
        PaletteScope(
          palette: Palette.dark,
          child: FluentApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Center(
                child: SizedBox(
                  width: 320,
                  height: 40,
                  child: PlayerBar(
                    name: 'Black',
                    detail: 'Player 2',
                    icon: FluentIcons.contact,
                    capturedPieces: ['♙'],
                    advantage: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$scale');
    }
  });
  testWidgets(
    'portrait board stays centred with controls visible, including system insets',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChessCoachApp(
          settings: AppSettings.memory(),
          store: EventStore.memory(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play').last);
      await tester.pumpAndSettle();
      final board = find.byKey(const ValueKey('play-board'));
      for (final example in [
        (size: const Size(390, 844), top: 0.0, bottom: 0.0),
        (size: const Size(360, 800), top: 24.0, bottom: 24.0),
        (size: const Size(390, 844), top: 44.0, bottom: 34.0),
        (size: const Size(412, 915), top: 24.0, bottom: 24.0),
      ]) {
        tester.view.physicalSize = example.size;
        tester.view.padding = FakeViewPadding(
          top: example.top,
          bottom: example.bottom,
        );
        tester.view.viewPadding = FakeViewPadding(
          top: example.top,
          bottom: example.bottom,
        );
        tester.binding.handleMetricsChanged();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$example');
        final boardRect = tester.getRect(board);
        final area = tester.getRect(find.byType(BoardLayout));
        expect(
          boardRect.width,
          example.size.width,
          reason: 'Use the full width',
        );
        expect(
          boardRect.center.dy,
          closeTo(area.center.dy, 1),
          reason: 'Centre the board itself',
        );
        expect(boardRect.center.dx, closeTo(area.center.dx, 1));
        expect(find.text('New').hitTestable(), findsOneWidget);
        expect(find.text('Hint').hitTestable(), findsOneWidget);
        expect(
          find
              .byWidgetPredicate(
                (w) =>
                    w is Semantics &&
                    w.properties.label == 'Open Coach suggestions',
              )
              .hitTestable(),
          findsOneWidget,
          reason: '$example',
        );
        expect(find.text('Training').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Real game').hitTestable());
        await tester.pumpAndSettle();
        expect(
          tester.getRect(board),
          boardRect,
          reason: 'Mode changes should not move the board',
        );
        await tester.tap(find.text('Training').hitTestable());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'game controller survives every shell breakpoint and PiP roundtrip',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      addTearDown(() => PictureInPicture.active.value = false);
      await tester.pumpWidget(
        ChessCoachApp(
          settings: AppSettings.memory(),
          store: EventStore.memory(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play').last);
      await tester.pumpAndSettle();
      final controller = tester
          .widget<Chessboard>(find.byKey(const ValueKey('play-board')))
          .controller;
      for (final size in [
        const Size(320, 480),
        const Size(700, 400),
        const Size(844, 390),
        const Size(1440, 900),
        const Size(600, 960),
        const Size(390, 380),
        const Size(240, 240),
      ]) {
        tester.view.physicalSize = size;
        tester.binding.handleMetricsChanged();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');
        expect(
          tester
              .widget<Chessboard>(find.byKey(const ValueKey('play-board')))
              .controller,
          same(controller),
          reason: 'Resizing must preserve the active game at $size',
        );
        expect(
          find.byIcon(FluentIcons.home_solid).hitTestable(),
          findsOneWidget,
        );
      }
      PictureInPicture.active.value = true;
      tester.view.physicalSize = const Size(320, 180);
      tester.binding.handleMetricsChanged();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(FluentIcons.home_solid), findsNothing);
      expect(find.textContaining('New game!').hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<Chessboard>(find.byKey(const ValueKey('play-board')))
            .controller,
        same(controller),
      );
      PictureInPicture.active.value = false;
      tester.view.physicalSize = const Size(390, 844);
      tester.binding.handleMetricsChanged();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Chessboard>(find.byKey(const ValueKey('play-board')))
            .controller,
        same(controller),
      );
      expect(find.text('Home').hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'short windows retain navigation on all main screens at large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 380);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ChessCoachApp(
          settings: AppSettings.memory(),
          store: EventStore.memory(),
        ),
      );
      await tester.pumpAndSettle();
      for (final icon in [
        FluentIcons.game,
        FluentIcons.puzzle,
        FluentIcons.education,
        FluentIcons.settings,
        FluentIcons.home_solid,
      ]) {
        await tester.tap(find.byIcon(icon).hitTestable().last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$icon');
        expect(
          find.byIcon(FluentIcons.home_solid).hitTestable(),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
