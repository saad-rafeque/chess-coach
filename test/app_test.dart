import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpAt(WidgetTester tester, Size size, AppSettings settings) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChessCoachApp(settings: settings));
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
  });
}
