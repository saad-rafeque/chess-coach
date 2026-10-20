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

  Color get glassFill => surface.withValues(alpha: brightness == Brightness.dark ? 0.76 : 0.88);
  Color get glassFillSubtle => surfaceAlt.withValues(alpha: brightness == Brightness.dark ? 0.55 : 0.70);
  Color get glassBorder => brightness == Brightness.dark ? const Color(0x28FFFFFF) : const Color(0x1E000000);
  Color get glassBorderSubtle => brightness == Brightness.dark ? const Color(0x18FFFFFF) : const Color(0x12000000);
  Color get specularBorder => brightness == Brightness.dark ? const Color(0x38FFFFFF) : const Color(0x28FFFFFF);

  BoxDecoration glassDecoration({
    double radius = 18,
    bool highlight = false,
    bool subtle = false,
    bool macosElevated = false,
  }) =>
      BoxDecoration(
        color: subtle ? glassFillSubtle : glassFill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: highlight
              ? accent
              : (subtle ? glassBorderSubtle : (macosElevated ? specularBorder : glassBorder)),
          width: highlight ? 1.6 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(
              alpha: brightness == Brightness.light ? 0.06 : 0.32,
            ),
            blurRadius: macosElevated ? 28 : 20,
            offset: Offset(0, macosElevated ? 10 : 6),
            spreadRadius: macosElevated ? 1 : 0,
          ),
          if (highlight)
            BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: 18,
              spreadRadius: 1.5,
            ),
        ],
      );

  static const light = Palette(
    brightness: Brightness.light,
    background: Color(0xFFF8FAFC),
    backgroundEnd: Color(0xFFEDF2F7),
    pane: Color(0xFFF1F5F9),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF1F5F9),
    border: Color(0xFFE2E8F0),
    text: Color(0xFF0F172A),
    muted: Color(0xFF64748B),
    accent: Color(0xFF0284C7),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF10B981),
  );

  static const dark = Palette(
    brightness: Brightness.dark,
    background: Color(0xFF0B0F17),
    backgroundEnd: Color(0xFF141A24),
    pane: Color(0xFF0A0D14),
    surface: Color(0xFF161D29),
    surfaceAlt: Color(0xFF1E2838),
    border: Color(0xFF263346),
    text: Color(0xFFF1F5F9),
    muted: Color(0xFF94A3B8),
    accent: Color(0xFF38BDF8),
    onAccent: Color(0xFF0B132B),
  );

  static const wooden = Palette(
    brightness: Brightness.dark,
    background: Color(0xFF1A120B),
    backgroundEnd: Color(0xFF2B1D12),
    pane: Color(0xFF150E09),
    surface: Color(0xFF332317),
    surfaceAlt: Color(0xFF3D2B1C),
    border: Color(0xFF553C28),
    text: Color(0xFFFDF4E7),
    muted: Color(0xFFC7AC93),
    accent: Color(0xFFF59E0B),
    onAccent: Color(0xFF1A120B),
    success: Color(0xFF84CC16),
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

FluentThemeData buildFluentTheme(Palette p, {String? fontFamily}) {
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
    fontFamily: fontFamily,
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
