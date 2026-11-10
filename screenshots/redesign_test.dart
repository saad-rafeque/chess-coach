// Visual QA of the redesigned app. Writes screenshots/out/redesign_*.png.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:chess_coach/app/board_style.dart';
import 'package:chess_coach/app/picture_in_picture.dart';
import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/data/curriculum.dart';
import 'package:chess_coach/main.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('redesign visual QA', (tester) async {
    for (final family in ['FluentIcons', 'SegoeIcons']) {
      await (FontLoader('packages/fluent_ui/$family')
            ..addFont(rootBundle.load('packages/fluent_ui/fonts/$family.ttf')))
          .load();
    }
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ??
        File(
          Platform.resolvedExecutable,
        ).parent.parent.parent.parent.parent.parent.path;
    final fontDir = Directory(
      '$flutterRoot/bin/cache/artifacts/material_fonts',
    );
    final roboto = FontLoader('Roboto');
    for (final file in fontDir.listSync().whereType<File>()) {
      if (file.path.endsWith('.ttf') && file.path.contains('Roboto-')) {
        roboto.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    }
    await roboto.load();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    addTearDown(() => PictureInPicture.active.value = false);
    final key = GlobalKey();
    final settings = AppSettings.memory();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ChessCoachApp(
          settings: settings,
          store: EventStore.memory(),
          fontFamily: 'Roboto',
        ),
      ),
    );
    Future<void> capture(String name, Size size) async {
      tester.view.physicalSize = size;
      tester.binding.handleMetricsChanged();
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => ChessgroundImages.instance.loadAll(
          BoardStyle.of(settings).pieces,
          devicePixelRatio: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('screenshots/out/redesign_$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('home_phone', const Size(390, 844));
    await tester.tap(find.text('Play').last);
    await capture('play_phone', const Size(390, 844));
    await capture('split', const Size(390, 380));
    await capture('landscape', const Size(844, 390));
    await capture('play_desktop', const Size(1440, 900));
    PictureInPicture.active.value = true;
    await capture('pip', const Size(320, 180));
    PictureInPicture.active.value = false;
    await capture('restored', const Size(390, 844));
    settings.theme = AppTheme.light;
    await capture('play_light', const Size(390, 844));
    await tester.tap(find.text('Home').last);
    await capture('home_light', const Size(390, 844));
    await capture('home_desktop', const Size(1440, 900));
    settings.theme = AppTheme.dark;
    await capture('home_phone_dark', const Size(390, 844));
    await tester.tap(find.text('Puzzles').last);
    await capture('puzzles_phone', const Size(390, 844));
    await capture('puzzles_split', const Size(390, 380));
    await capture('puzzles_landscape', const Size(844, 390));
    await capture('puzzles_restored', const Size(390, 844));
    await tester.tap(find.text('Lessons').last);
    await capture('lessons_phone', const Size(390, 844));
    await tester.tap(find.text(allLessons.first.title));
    await capture('lesson_phone', const Size(390, 844));
    await capture('lesson_split', const Size(390, 380));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
