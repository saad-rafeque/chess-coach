import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/app/updater.dart';
import 'package:chess_coach/main.dart';
import 'package:fluent_ui/fluent_ui.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a new version is offered once per start, with its notes', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final updater = Updater(kind: InstallKind.other, environment: const {});
    await tester.pumpWidget(ChessCoachApp(settings: AppSettings.memory(), updater: updater));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);

    updater
      ..available = const ReleaseInfo(version: '9.9.9', notes: '## Fixed\n- **Sign-in** on phones', pageUrl: '')
      ..notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('• Sign-in on phones'), findsOneWidget);
    expect(find.text('Open download page'), findsOneWidget, reason: 'no verified file for this install');

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    updater.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing, reason: 'not again until the next start');
  });
}
