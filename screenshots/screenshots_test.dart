// Renders every main screen to PNG files in screenshots/out/.
// Run with: flutter test screenshots/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chess_coach/app/board_style.dart';
import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/main.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
  final icons = FontLoader('packages/fluent_ui/FluentIcons')
    ..addFont(rootBundle.load('packages/fluent_ui/fonts/FluentIcons.ttf'));
  await icons.load();
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
}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final settings = AppSettings.memory()..theme = theme;
  await tester.pumpWidget(RepaintBoundary(
    key: _root,
    child: ChessCoachApp(settings: settings, fontFamily: 'Roboto'),
  ));
  for (final page in pages) {
    if (page != 'Home') {
      await tester.tap(find.text(page).last);
    }
    await _settle(tester, theme, dpr);
    await _capture(tester, '${device}_${theme.name}_${page.toLowerCase()}', dpr);
  }
}

void main() {
  setUpAll(_loadFonts);

  const all = ['Home', 'Play', 'Puzzles', 'Lessons', 'Settings'];
  for (final theme in AppTheme.values) {
    testWidgets('desktop ${theme.name}', (tester) async {
      await _shoot(tester,
          device: 'desktop',
          size: const Size(1440, 900),
          dpr: 1,
          theme: theme,
          pages: theme == AppTheme.dark ? all : const ['Home', 'Play', 'Settings']);
    });
    testWidgets('phone ${theme.name}', (tester) async {
      await _shoot(tester,
          device: 'phone',
          size: const Size(390, 844),
          dpr: 2,
          theme: theme,
          pages: theme == AppTheme.dark ? all : const ['Home', 'Play']);
    });
  }
}
