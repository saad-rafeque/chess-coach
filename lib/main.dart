import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import 'app/settings.dart';
import 'app/shell.dart';
import 'app/theme.dart';
import 'engine/engine_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final engine = EngineHost();
  unawaited(engine.engine); // warm up Stockfish in the background
  runApp(ChessCoachApp(settings: settings, engine: engine));
}

class ChessCoachApp extends StatelessWidget {
  const ChessCoachApp({super.key, required this.settings, this.engine, this.fontFamily});

  final AppSettings settings;

  /// Stockfish host; tests leave it null to run without an engine.
  final EngineHost? engine;

  /// Overrides the platform font (used by the screenshot tests).
  final String? fontFamily;

  static final _offline = EngineHost(starter: () => Future.error(UnsupportedError('Engine disabled')));

  @override
  Widget build(BuildContext context) {
    return EngineScope(
      host: engine ?? _offline,
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
    );
  }
}
