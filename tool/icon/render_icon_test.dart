// Renders the app icon to assets/icon/. Run with: flutter test tool/icon/render_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show PieceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 1024.0;
final _key = GlobalKey();

/// Knight on a blue gradient tile. [foregroundOnly] leaves the background
/// transparent and adds the safe-zone padding Android adaptive icons need.
Widget _icon({required bool foregroundOnly}) {
  final knight = SizedBox.expand(
    child: Image(
      image: PieceSet.cburnettAssets[PieceKind.whiteKnight]!,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    ),
  );
  return RepaintBoundary(
    key: _key,
    child: SizedBox.square(
      dimension: _size,
      child: foregroundOnly
          ? Padding(padding: const EdgeInsets.all(_size * 0.24), child: knight)
          : DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_size * 0.22),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3B82F6), Color(0xFF1E3A8A)],
                ),
              ),
              child: Padding(padding: const EdgeInsets.all(_size * 0.14), child: knight),
            ),
    ),
  );
}

Future<void> _render(WidgetTester tester, String path, {required bool foregroundOnly}) async {
  tester.view.physicalSize = const Size(_size, _size);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topLeft, child: _icon(foregroundOnly: foregroundOnly)),
  ));
  await tester.runAsync(() async {
    await precacheImage(PieceSet.cburnettAssets[PieceKind.whiteKnight]!, _key.currentContext!);
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('app icon', (t) => _render(t, 'assets/icon/icon.png', foregroundOnly: false));
  testWidgets('adaptive foreground', (t) => _render(t, 'assets/icon/icon_fg.png', foregroundOnly: true));
}
