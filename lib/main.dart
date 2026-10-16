import 'package:fluent_ui/fluent_ui.dart';

import 'app/settings.dart';
import 'app/shell.dart';
import 'app/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(ChessCoachApp(settings: settings));
}

class ChessCoachApp extends StatelessWidget {
  const ChessCoachApp({super.key, required this.settings, this.fontFamily});

  final AppSettings settings;

  /// Overrides the platform font (used by the screenshot tests).
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
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
    );
  }
}
