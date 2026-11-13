import 'dart:async';

import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/app/theme.dart';
import 'package:chess_coach/app/updater.dart';
import 'package:chess_coach/coach/llm/coach_voice.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/engine/engine_host.dart';
import 'package:chess_coach/screens/lessons_page.dart';
import 'package:chess_coach/screens/play_page.dart';
import 'package:chess_coach/screens/settings_page.dart';
import 'package:chess_coach/sync/google_auth.dart';
import 'package:chess_coach/sync/sync_service.dart';
import 'package:chess_coach/widgets/update_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final page in <String, Widget>{
    'settings': const SettingsPage(),
    'lessons': const LessonsPage(),
    'play with a long coach name': const PlayPage(),
  }.entries) {
    testWidgets('${page.key} fits compact and desktop windows at 200% text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final settings = AppSettings.memory()
        ..coachName = 'A very long coach name';
      final store = EventStore.memory();
      final sync = SyncService(
        store: store,
        settings: settings,
        config: const OAuthConfig(clientId: '', clientSecret: ''),
      );
      addTearDown(sync.dispose);
      final host = EngineHost(
        starter: () => Future.error(StateError('offline')),
      );
      addTearDown(() {
        unawaited(host.dispose());
      });
      for (final style in InterfaceStyle.values) {
        settings.interfaceStyle = style;
        final palette = Palette.dark.withStyle(style);
        for (final size in [
          const Size(240, 380),
          const Size(320, 480),
          const Size(700, 320),
          const Size(1280, 720),
        ]) {
          tester.view.physicalSize = size;
          tester.binding.handleMetricsChanged();
          await tester.pumpWidget(
            EngineScope(
              host: host,
              child: SettingsScope(
                settings: settings,
                child: StoreScope(
                  store: store,
                  child: VoiceScope(
                    voice: CoachVoice.off(),
                    child: SyncScope(
                      sync: sync,
                      child: UpdateScope(
                        updater: Updater(kind: InstallKind.other),
                        child: PaletteScope(
                          palette: palette,
                          child: FluentApp(
                            theme: buildFluentTheme(palette),
                            home: page.value,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$style / $size');
          if (page.value is PlayPage && size == const Size(700, 320)) {
            await tester.ensureVisible(find.text('New'));
            await tester.tap(find.text('New').hitTestable());
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'New game / $style');
            await tester.ensureVisible(
              find.text('Match my level automatically'),
            );
            await tester.pumpAndSettle();
            expect(
              find.text('Match my level automatically').hitTestable(),
              findsOneWidget,
            );
            await tester.tap(find.text('Cancel'));
            await tester.pumpAndSettle();
          }
        }
      }
    });
  }
}
