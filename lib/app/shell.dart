import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show PieceKind;
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
    final p = Palette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    if (width < mobileBreakpoint) {
      return Column(children: [
        Expanded(child: _stack),
        _BottomNav(index: _index, onTap: _go),
      ]);
    }
    PaneItem item(_Dest d) => PaneItem(icon: Icon(d.icon), title: Text(d.label), body: const SizedBox.shrink());
    return NavigationView(
      paneBodyBuilder: (item, body) => _stack,
      pane: NavigationPane(
        selected: _index,
        onChanged: _go,
        displayMode: width >= 1200 ? PaneDisplayMode.expanded : PaneDisplayMode.compact,
        header: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            const _Logo(size: 26),
            const SizedBox(width: 10),
            Text('Chess Coach', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: p.text)),
          ]),
        ),
        items: [for (final d in _dests.take(4)) item(d)],
        footerItems: [item(_dests.last)],
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
    return Container(
      decoration: BoxDecoration(
        color: p.pane,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        // Large system fonts would not fit the bar; labels grow a little, icons say the rest.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.15,
          child: SizedBox(
            height: 64,
            child: Row(children: [
              for (final (i, d) in _dests.indexed)
                Expanded(
                  child: HoverButton(
                    onPressed: () => onTap(i),
                    builder: (context, states) {
                      final selected = i == index;
                      final color = selected ? p.accent : p.muted;
                      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        AnimatedContainer(
                          duration: motion(context, const Duration(milliseconds: 180)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                          decoration: BoxDecoration(
                            color: selected ? p.accent.withValues(alpha: 0.15) : null,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(d.icon, size: 18, color: color),
                        ),
                        const SizedBox(height: 3),
                        Text(d.label,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(
                                fontSize: 11,
                                color: color,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                      ]);
                    },
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Simple app mark: a rounded tile with a knight glyph.
class _Logo extends StatelessWidget {
  const _Logo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [p.accent, Color.lerp(p.accent, const Color(0xFF000000), 0.3)!]),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      padding: EdgeInsets.all(size * 0.12),
      child: Image(image: PieceSet.cburnettAssets[PieceKind.whiteKnight]!),
    );
  }
}
