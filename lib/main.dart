import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import 'app/settings.dart';
import 'app/shell.dart';
import 'app/theme.dart';
import 'coach/llm/coach_voice.dart';
import 'coach/llm/model_store.dart';
import 'data/event_store.dart';
import 'engine/engine_host.dart';
import 'sync/google_auth.dart';
import 'sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final engine = EngineHost();
  unawaited(engine.engine); // warm up Stockfish in the background
  EventStore store;
  try {
    store = await EventStore.open(device: settings.deviceId);
  } catch (e) {
    debugPrint('Storage unavailable, keeping data in memory: $e');
    store = EventStore.memory(device: settings.deviceId);
  }
  final models = ModelStore();
  unawaited(models.refresh());
  final voice = CoachVoice(settings: settings, models: models);
  final sync = SyncService(store: store, settings: settings)..start();
  runApp(ChessCoachApp(settings: settings, engine: engine, store: store, voice: voice, sync: sync));
}

class ChessCoachApp extends StatelessWidget {
  const ChessCoachApp(
      {super.key, required this.settings, this.engine, this.store, this.voice, this.sync, this.fontFamily});

  final AppSettings settings;

  /// Saved games, reviews, puzzle attempts; tests leave it null for an in-memory store.
  final EventStore? store;

  /// Stockfish host; tests leave it null to run without an engine.
  final EngineHost? engine;

  /// Optional language model that rephrases explanations; tests leave it null (templates only).
  final CoachVoice? voice;

  /// Google Drive sync; tests leave it null (sync off).
  final SyncService? sync;

  /// Overrides the platform font (used by the screenshot tests).
  final String? fontFamily;

  static final _offline = EngineHost(starter: () => Future.error(UnsupportedError('Engine disabled')));
  static final _memory = EventStore.memory();
  static final _silent = CoachVoice.off();
  static final _noSync = SyncService(
      store: _memory, settings: AppSettings.memory(), config: const OAuthConfig(clientId: '', clientSecret: ''));

  @override
  Widget build(BuildContext context) {
    return EngineScope(
      host: engine ?? _offline,
      child: StoreScope(
        store: store ?? _memory,
        child: VoiceScope(
          voice: voice ?? _silent,
          child: SyncScope(
            sync: sync ?? _noSync,
            child: SettingsScope(
              settings: settings,
              child: ListenableBuilder(
                listenable: settings,
                builder: (context, _) {
                  final palette = Palette.forTheme(settings.theme);
                  return PaletteScope(
                    palette: palette,
                    child: FluentApp(
                      title: 'Chess Coach',
                      debugShowCheckedModeBanner: false,
                      theme: buildFluentTheme(palette, fontFamily: fontFamily),
                      home: const AppShell(),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
