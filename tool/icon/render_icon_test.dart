// Generate the shared vector mark as launcher assets: flutter test tool/icon/render_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:chess_coach/widgets/coach_mark.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final kind in ['icon', 'icon_fg', 'icon_bg']) {
    testWidgets('render $kind', (tester) async {
      tester.view.physicalSize = const Size(1024, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: CoachMark(
              foregroundOnly: kind == 'icon_fg',
              backgroundOnly: kind == 'icon_bg',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          'assets/icon/$kind.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
