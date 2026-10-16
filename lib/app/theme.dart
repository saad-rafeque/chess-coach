import 'package:fluent_ui/fluent_ui.dart';

import 'settings.dart';

/// Colours used by the app's own widgets, one set per theme.
class Palette {
  const Palette({
    required this.brightness,
    required this.background,
    required this.backgroundEnd,
    required this.pane,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    this.success = const Color(0xFF22C55E),
    this.warning = const Color(0xFFF59E0B),
    this.danger = const Color(0xFFEF4444),
    this.woodGrain = false,
  });

  final Brightness brightness;
  final Color background;
  final Color backgroundEnd;
  final Color pane;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color danger;
  final bool woodGrain;

  static const light = Palette(
    brightness: Brightness.light,
    background: Color(0xFFF4F5F8),
    backgroundEnd: Color(0xFFE8EDF5),
    pane: Color(0xFFEDEFF3),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF5F6F9),
    border: Color(0xFFE1E4EA),
    text: Color(0xFF1B1D22),
    muted: Color(0xFF666C76),
    accent: Color(0xFF2563EB),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF16A34A),
  );

  static const dark = Palette(
    brightness: Brightness.dark,
    background: Color(0xFF18191C),
    backgroundEnd: Color(0xFF1F2228),
    pane: Color(0xFF141518),
    surface: Color(0xFF25272C),
    surfaceAlt: Color(0xFF2D3036),
    border: Color(0xFF363A42),
    text: Color(0xFFF1F2F5),
    muted: Color(0xFFA0A5AF),
    accent: Color(0xFF60A5FA),
    onAccent: Color(0xFF0B1220),
  );

  static const wooden = Palette(
    brightness: Brightness.dark,
    background: Color(0xFF2A1C12),
    backgroundEnd: Color(0xFF3A2616),
    pane: Color(0xFF22170F),
    surface: Color(0xFF3F2B1D),
    surfaceAlt: Color(0xFF4A3323),
    border: Color(0xFF5E4330),
    text: Color(0xFFF7ECDD),
    muted: Color(0xFFCDB69B),
    accent: Color(0xFFE3A857),
    onAccent: Color(0xFF2A1C12),
    success: Color(0xFF8BC34A),
    woodGrain: true,
  );

  static Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaletteScope>()!.palette;

  static Palette forTheme(AppTheme theme) => switch (theme) {
        AppTheme.light => light,
        AppTheme.dark => dark,
        AppTheme.wooden => wooden,
      };
}

class PaletteScope extends InheritedWidget {
  const PaletteScope({super.key, required this.palette, required super.child});

  final Palette palette;

  @override
  bool updateShouldNotify(PaletteScope oldWidget) => palette != oldWidget.palette;
}

FluentThemeData buildFluentTheme(Palette p) {
  final accent = AccentColor.swatch({
    'darkest': Color.lerp(p.accent, const Color(0xFF000000), 0.45)!,
    'darker': Color.lerp(p.accent, const Color(0xFF000000), 0.3)!,
    'dark': Color.lerp(p.accent, const Color(0xFF000000), 0.15)!,
    'normal': p.accent,
    'light': Color.lerp(p.accent, const Color(0xFFFFFFFF), 0.15)!,
    'lighter': Color.lerp(p.accent, const Color(0xFFFFFFFF), 0.3)!,
    'lightest': Color.lerp(p.accent, const Color(0xFFFFFFFF), 0.45)!,
  });
  return FluentThemeData(
    brightness: p.brightness,
    accentColor: accent,
    scaffoldBackgroundColor: p.background,
    cardColor: p.surface,
    micaBackgroundColor: p.background,
    visualDensity: VisualDensity.standard,
    navigationPaneTheme: NavigationPaneThemeData(backgroundColor: p.pane),
    resources: p.brightness == Brightness.light
        ? const ResourceDictionary.light()
        : const ResourceDictionary.dark(),
  );
}
