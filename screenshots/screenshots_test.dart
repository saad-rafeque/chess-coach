// Renders every main screen to PNG files in screenshots/out/.
// Run with: flutter test screenshots/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chess_coach/app/board_style.dart';
import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/main.dart';
import 'package:chess_coach/puzzles/puzzle.dart';
import 'package:chess_coach/screens/session_page.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/fixtures.dart';

final _root = GlobalKey();

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final fonts = Directory('$flutterRoot/bin/cache/artifacts/material_fonts');
  final roboto = FontLoader('Roboto');
  for (final f in fonts.existsSync() ? fonts.listSync().whereType<File>() : const <File>[]) {
    final name = f.uri.pathSegments.last;
    if (name.startsWith('Roboto-') && name.endsWith('.ttf')) {
      roboto.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
  }
  await roboto.load();
  for (final family in ['FluentIcons', 'SegoeIcons']) {
    final loader = FontLoader('packages/fluent_ui/$family')
      ..addFont(rootBundle.load('packages/fluent_ui/fonts/$family.ttf'));
    await loader.load();
  }
}

Future<void> _settle(WidgetTester tester, AppTheme theme, double dpr) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final style = BoardStyle.forTheme(theme);
    await ChessgroundImages.instance.loadAll(style.pieces, devicePixelRatio: dpr);
    final bg = style.colors.background;
    if (bg is ImageChessboardBackground) {
      await precacheImage(bg.image, _root.currentContext!);
    }
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name, double dpr) async {
  final boundary = _root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('screenshots/out/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _shoot(
  WidgetTester tester, {
  required String device,
  required Size size,
  required double dpr,
  required AppTheme theme,
  required List<String> pages,
  EventStore? store,
}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  TrainingSession.current.value = null;
  final settings = AppSettings.memory()..theme = theme;
  await tester.runAsync(PuzzleBank.shared);
  await tester.pumpWidget(RepaintBoundary(
    key: _root,
    child: ChessCoachApp(settings: settings, store: store ?? EventStore.memory(), fontFamily: 'Roboto'),
  ));
  for (final page in pages) {
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    if (nav.canPop()) {
      nav.pop();
      await tester.pumpAndSettle();
    }
    if (page == 'Review') {
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review').first);
      await _settle(tester, theme, dpr);
      // The coach's walkthrough of the blunders (under the board on phones, beside it on desktop).
      await tester.ensureVisible(find.text('Blunders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blunders'));
    } else if (page == 'Session') {
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('1 hour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 hour'));
    } else if (page == 'Cards') {
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('to review'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('to review'));
    } else if (page == 'Lesson') {
      await tester.tap(find.text('Lessons').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opening principles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
    } else if (page != 'Home') {
      await tester.tap(find.text(page).last);
    }
    await _settle(tester, theme, dpr);
    await _capture(tester, '${device}_${theme.name}_${page.toLowerCase()}', dpr);
  }
}

/// The first-start setup on a phone, one picture per step.
Future<void> _shootSetup(WidgetTester tester) async {
  const dpr = 2.0;
  tester.view.physicalSize = const Size(390, 844) * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final settings = AppSettings.memory()..onboarded = false;
  await tester.pumpWidget(RepaintBoundary(
    key: _root,
    child: ChessCoachApp(settings: settings, store: EventStore.memory(), fontFamily: 'Roboto'),
  ));
  Future<void> shot(String name) async {
    await _settle(tester, settings.theme, dpr);
    await _capture(tester, 'phone_setup_$name', dpr);
  }

  await shot('welcome');
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(EditableText), 'Saad');
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Nova'));
  await shot('coach');
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Beginner'));
  await shot('level');
  await tester.tap(find.text('Continue'));
  await shot('look');
  await tester.tap(find.text('Continue'));
  await shot('done');
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('phone setup', _shootSetup);

  const all = ['Home', 'Play', 'Puzzles', 'Lessons', 'Settings'];
  for (final theme in AppTheme.values) {
    testWidgets('desktop ${theme.name}', (tester) async {
      await _shoot(tester,
          device: 'desktop',
          size: const Size(1440, 900),
          dpr: 1,
          theme: theme,
          store: await storeWithReviewedGame(),
          pages: theme == AppTheme.dark ? [...all, 'Review', 'Lesson', 'Session', 'Cards'] : const ['Home', 'Play', 'Settings']);
    });
    testWidgets('phone ${theme.name}', (tester) async {
      await _shoot(tester,
          device: 'phone',
          size: const Size(390, 844),
          dpr: 2,
          theme: theme,
          store: await storeWithReviewedGame(),
          pages: theme == AppTheme.dark ? [...all, 'Review', 'Lesson', 'Session', 'Cards'] : const ['Home', 'Play']);
    });
  }
}
