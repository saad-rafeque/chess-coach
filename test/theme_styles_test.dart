import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/app/theme.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/main.dart';
import 'package:chess_coach/widgets/board_layout.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('all looks persist and sync, retaining original themes', () async {
    SharedPreferences.setMockInitialValues({'theme': 'wooden'});
    final settings = await AppSettings.load();
    expect(settings.theme, AppTheme.wooden);
    expect(settings.interfaceStyle, InterfaceStyle.glass);
    for (final theme in AppTheme.values) {
      for (final style in InterfaceStyle.values) {
        settings.theme = theme;
        settings.interfaceStyle = style;
        final loaded = await AppSettings.load();
        expect(loaded.theme, theme);
        expect(loaded.interfaceStyle, style);
        final synced = AppSettings.memory()
          ..applySync(
            settings.toSyncJson(),
            DateTime.now().add(const Duration(days: 1)),
          );
        expect(synced.theme, theme);
        expect(synced.interfaceStyle, style);
      }
    }
  });

  testWidgets(
    'all themes and interface styles render on phone and short split',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = AppSettings.memory();
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(
        ChessCoachApp(settings: settings, store: EventStore.memory()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play').last);
      await tester.pumpAndSettle();
      for (final theme in AppTheme.values) {
        for (final style in InterfaceStyle.values) {
          settings.theme = theme;
          settings.interfaceStyle = style;
          for (final size in [const Size(390, 844), const Size(320, 320)]) {
            tester.view.physicalSize = size;
            tester.binding.handleMetricsChanged();
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$theme/$style/$size',
            );
            expect(
              Palette.of(
                tester.element(find.byType(BoardLayout)),
              ).interfaceStyle,
              style,
            );
            expect(find.text('Hint').hitTestable(), findsOneWidget);
          }
        }
      }
    },
  );
}
