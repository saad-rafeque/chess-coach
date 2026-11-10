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
    this.interfaceStyle = InterfaceStyle.glass,
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
  final InterfaceStyle interfaceStyle;
  bool get isGlass => interfaceStyle == InterfaceStyle.glass;
  double corner(double radius) =>
      interfaceStyle == InterfaceStyle.fluent ? radius.clamp(0, 12) : radius;

  Palette withStyle(InterfaceStyle style) => Palette(
    brightness: brightness,
    background: background,
    backgroundEnd: backgroundEnd,
    pane: pane,
    surface: surface,
    surfaceAlt: surfaceAlt,
    border: border,
    text: text,
    muted: muted,
    accent: accent,
    onAccent: onAccent,
    success: success,
    warning: warning,
    danger: danger,
    woodGrain: woodGrain,
    interfaceStyle: style,
  );

  Color get glassFill => isGlass ? surface.withValues(alpha: 0.88) : surface;
  Color get glassFillSubtle =>
      isGlass ? surfaceAlt.withValues(alpha: 0.64) : surfaceAlt;
  Color get glassBorder => Color.lerp(border, text, 0.12)!;
  Color get glassBorderSubtle => border.withValues(alpha: 0.65);
  Color get specularBorder => text.withValues(alpha: 0.20);

  // Translucent layers and a static light falloff give the glass finish without
  // a backdrop blur pass on every card while pieces and lists are moving.
  BoxDecoration glassDecoration({
    double radius = 24,
    bool highlight = false,
    bool subtle = false,
    bool macosElevated = false,
  }) => BoxDecoration(
    color: isGlass
        ? null
        : Color.lerp(
            subtle ? surfaceAlt : surface,
            accent,
            highlight ? 0.13 : 0,
          ),
    gradient: !isGlass
        ? null
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(
                surface,
                highlight ? accent : text,
                highlight ? 0.14 : 0.06,
              )!.withValues(alpha: subtle ? 0.76 : 0.96),
              (subtle ? surfaceAlt : surface).withValues(
                alpha: subtle ? 0.56 : 0.82,
              ),
            ],
          ),
    borderRadius: BorderRadius.circular(corner(radius)),
    border: Border.all(
      color: highlight ? accent.withValues(alpha: 0.32) : glassBorder,
    ),
    boxShadow: !isGlass || (subtle && !macosElevated)
        ? null
        : [
            BoxShadow(
              color: const Color(
                0xFF09140B,
              ).withValues(alpha: brightness == Brightness.dark ? 0.16 : 0.06),
              blurRadius: macosElevated ? 22 : 14,
              offset: const Offset(0, 5),
            ),
          ],
  );

  static const light = Palette(
    brightness: Brightness.light,
    background: Color(0xFFF3F6EF),
    backgroundEnd: Color(0xFFE5EDE1),
    pane: Color(0xFFEDF2E8),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEAF0E5),
    border: Color(0xFFD7E1CF),
    text: Color(0xFF263025),
    muted: Color(0xFF5D6B58),
    accent: Color(0xFF507C37),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF10B981),
  );

  static const dark = Palette(
    brightness: Brightness.dark,
    background: Color(0xFF2A342D),
    backgroundEnd: Color(0xFF202521),
    pane: Color(0xFF242D26),
    surface: Color(0xFF323D34),
    surfaceAlt: Color(0xFF39453B),
    border: Color(0xFF49564A),
    text: Color(0xFFF3F5EE),
    muted: Color(0xFFBBC5B7),
    accent: Color(0xFFB4D992),
    onAccent: Color(0xFF202719),
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

  static const midnight = Palette(
    brightness: Brightness.dark,
    background: Color(0xFF172638),
    backgroundEnd: Color(0xFF101721),
    pane: Color(0xFF172230),
    surface: Color(0xFF223246),
    surfaceAlt: Color(0xFF2B4057),
    border: Color(0xFF40556C),
    text: Color(0xFFF0F5FC),
    muted: Color(0xFFAFBED1),
    accent: Color(0xFF9CCAFF),
    onAccent: Color(0xFF112840),
  );
  static const amethyst = Palette(
    brightness: Brightness.dark,
    background: Color(0xFF30243D),
    backgroundEnd: Color(0xFF1C1826),
    pane: Color(0xFF271F32),
    surface: Color(0xFF3A2E48),
    surfaceAlt: Color(0xFF493957),
    border: Color(0xFF62516E),
    text: Color(0xFFF8F1FC),
    muted: Color(0xFFC8B9D1),
    accent: Color(0xFFD6B5FA),
    onAccent: Color(0xFF30203E),
  );
  static const sand = Palette(
    brightness: Brightness.light,
    background: Color(0xFFFAF4E9),
    backgroundEnd: Color(0xFFEDE1CD),
    pane: Color(0xFFF2E7D5),
    surface: Color(0xFFFFFBF4),
    surfaceAlt: Color(0xFFF0E5D1),
    border: Color(0xFFD9C8AD),
    text: Color(0xFF372C20),
    muted: Color(0xFF75634D),
    accent: Color(0xFF8C5725),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF36703F),
  );

  static Palette of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaletteScope>()?.palette ??
      dark;

  static Palette forTheme(AppTheme theme) => switch (theme) {
    AppTheme.light => light,
    AppTheme.dark => dark,
    AppTheme.wooden => wooden,
    AppTheme.midnight => midnight,
    AppTheme.amethyst => amethyst,
    AppTheme.sand => sand,
  };
}

class PaletteScope extends InheritedWidget {
  const PaletteScope({super.key, required this.palette, required super.child});

  final Palette palette;

  @override
  bool updateShouldNotify(PaletteScope oldWidget) =>
      palette != oldWidget.palette;
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
    buttonTheme: ButtonThemeData(
      defaultButtonStyle: ButtonStyle(
        shape: WidgetStateProperty.resolveWith(
          (states) => RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(p.corner(16)),
            side: BorderSide(
              color: states.isHovered ? p.glassBorder : p.glassBorderSubtle,
            ),
          ),
        ),
      ),
      filledButtonStyle: const ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      ),
    ),
    navigationPaneTheme: NavigationPaneThemeData(backgroundColor: p.pane),
    resources: p.brightness == Brightness.light
        ? const ResourceDictionary.light()
        : const ResourceDictionary.dark(),
  );
}
