import 'dart:ui' show ImageFilter;

import 'package:fluent_ui/fluent_ui.dart';

import '../screens/home_page.dart';
import '../screens/lessons_page.dart';
import '../screens/play_page.dart';
import '../screens/puzzles_page.dart';
import '../screens/settings_page.dart';
import '../widgets/common.dart';
import 'theme.dart';

class _Dest {
  const _Dest(this.label, this.icon);

  final String label;
  final IconData icon;
}

const _dests = [
  _Dest('Home', FluentIcons.home),
  _Dest('Play', FluentIcons.game),
  _Dest('Puzzles', FluentIcons.puzzle),
  _Dest('Lessons', FluentIcons.education),
  _Dest('Settings', FluentIcons.settings),
];

/// Side navigation on desktop, bottom bar on phones. Pages stay alive when
/// switching tabs so a running game isn't lost.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  late final List<Widget> _pages = [
    HomePage(onNavigate: _go),
    const PlayPage(),
    const PuzzlesPage(),
    const LessonsPage(),
    const SettingsPage(),
  ];

  void _go(int i) => setState(() => _index = i);

  Widget get _stack => IndexedStack(index: _index, children: _pages);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < mobileBreakpoint) {
      final shortWindow = MediaQuery.sizeOf(context).height < 430;
      return Column(
        children: [
          Expanded(child: _stack),
          if (!shortWindow) _BottomNav(index: _index, onTap: _go),
        ],
      );
    }
    return _MacOsDesktopShell(
      index: _index,
      onTap: _go,
      child: _stack,
    );
  }
}

class _MacOsDesktopShell extends StatelessWidget {
  const _MacOsDesktopShell({
    required this.index,
    required this.onTap,
    required this.child,
  });

  final int index;
  final ValueChanged<int> onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 1000;
    final sidebarWidth = compact ? 68.0 : 230.0;

    return Container(
      decoration: BoxDecoration(
        color: p.background,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(
              p.background,
              p.accent,
              p.brightness == Brightness.dark ? 0.05 : 0.02,
            )!,
            p.background,
            p.backgroundEnd,
          ],
        ),
      ),
      child: Row(
        children: [
          // Authentic macOS Vibrant Acrylic Sidebar
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: sidebarWidth,
                decoration: BoxDecoration(
                  color: p.pane.withValues(
                    alpha: p.brightness == Brightness.dark ? 0.75 : 0.88,
                  ),
                  border: Border(
                    right: BorderSide(color: p.glassBorder, width: 1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF000000).withValues(
                        alpha: p.brightness == Brightness.dark ? 0.25 : 0.04,
                      ),
                      blurRadius: 16,
                      offset: const Offset(2, 0),
                    ),
                  ],
                ),
                child: SafeArea(
                  right: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // macOS Window Traffic Lights
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 16 : 20,
                          16,
                          16,
                          compact ? 16 : 20,
                        ),
                        child: const MacOsTrafficLights(),
                      ),
                      // App Branding
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 12 : 18,
                        ),
                        child: Row(
                          children: [
                            const AppLogo(size: 28),
                            if (!compact) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Chess Coach',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: p.text,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    Text(
                                      'Pro Edition',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: p.accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (!compact)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 6,
                          ),
                          child: Text(
                            'CHESS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: p.muted.withValues(alpha: 0.7),
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      // Main navigation items
                      for (var i = 0; i < 4; i++)
                        _MacOsSidebarItem(
                          dest: _dests[i],
                          selected: index == i,
                          compact: compact,
                          onTap: () => onTap(i),
                        ),
                      const Spacer(),
                      if (!compact)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 6,
                          ),
                          child: Text(
                            'SYSTEM',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: p.muted.withValues(alpha: 0.7),
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      _MacOsSidebarItem(
                        dest: _dests.last,
                        selected: index == 4,
                        compact: compact,
                        onTap: () => onTap(4),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Main Content View
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _MacOsSidebarItem extends StatelessWidget {
  const _MacOsSidebarItem({
    required this.dest,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final _Dest dest;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: 2,
      ),
      child: HoverButton(
        onPressed: onTap,
        builder: (context, states) {
          final hovered = states.isHovered;
          final color = selected
              ? (p.brightness == Brightness.dark
                  ? const Color(0xFFFFFFFF)
                  : p.accent)
              : (hovered ? p.text : p.muted);
          return AnimatedScale(
            duration: motion(context, const Duration(milliseconds: 120)),
            curve: Curves.easeOutCubic,
            scale: states.isPressed ? 0.98 : (hovered ? 1.01 : 1.0),
            child: AnimatedContainer(
              duration: motion(context, const Duration(milliseconds: 140)),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? p.accent.withValues(
                        alpha: p.brightness == Brightness.dark ? 0.22 : 0.15,
                      )
                    : (hovered ? p.surface.withValues(alpha: 0.5) : null),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? p.accent.withValues(alpha: 0.45)
                      : (hovered ? p.glassBorderSubtle : Colors.transparent),
                  width: 1,
                ),
                boxShadow: [
                  if (selected)
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.18),
                      blurRadius: 10,
                      spreadRadius: 0.5,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: Row(
                mainAxisAlignment: compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(dest.icon, size: 17, color: color),
                  if (!compact) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        dest.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ),
                    if (selected)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: p.accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: p.accent,
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: p.pane.withValues(alpha: p.brightness == Brightness.dark ? 0.78 : 0.90),
            border: Border(top: BorderSide(color: p.glassBorder)),
          ),
          child: SafeArea(
            top: false,
            // Large system fonts would not fit the bar; labels grow a little, icons say the rest.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.15,
              child: SizedBox(
                height: 58,
                child: Row(
                  children: [
                    for (final (i, d) in _dests.indexed)
                      Expanded(
                        child: HoverButton(
                          onPressed: () => onTap(i),
                          builder: (context, states) {
                            final selected = i == index;
                            final color = selected ? p.accent : p.muted;
                            return AnimatedScale(
                              duration: motion(
                                context,
                                const Duration(milliseconds: 140),
                              ),
                              curve: Curves.easeOutCubic,
                              scale: states.isPressed ? 0.92 : 1.0,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedContainer(
                                    duration: motion(
                                      context,
                                      const Duration(milliseconds: 180),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? p.accent.withValues(alpha: 0.16)
                                          : null,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [
                                        if (selected)
                                          BoxShadow(
                                            color: p.accent.withValues(alpha: 0.18),
                                            blurRadius: 10,
                                            spreadRadius: 0.5,
                                          ),
                                      ],
                                    ),
                                    child: Icon(d.icon, size: 18, color: color),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    d.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: color,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
