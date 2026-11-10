import 'package:fluent_ui/fluent_ui.dart';

import '../screens/home_page.dart';
import '../screens/lessons_page.dart';
import '../screens/play_page.dart';
import '../screens/puzzles_page.dart';
import '../screens/settings_page.dart';
import '../widgets/common.dart';
import 'picture_in_picture.dart';
import 'theme.dart';

const _labels = ['Home', 'Play', 'Puzzles', 'Lessons', 'Settings'];
const _icons = [
  FluentIcons.home_solid,
  FluentIcons.game,
  FluentIcons.puzzle,
  FluentIcons.education,
  FluentIcons.settings,
];

/// One stable page tree across phone, landscape, split-screen and PiP.
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  late final _fade = Tween<double>(
    begin: 0.78,
    end: 1,
  ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_transition);
  late final _transition = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 180),
  );
  int _index = 0;
  final _visited = <int>{0};
  late final _pages = <Widget>[
    HomePage(onNavigate: _go),
    const PlayPage(),
    const PuzzlesPage(),
    const LessonsPage(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    PictureInPicture.initialize();
    PictureInPicture.active.addListener(_pipChanged);
  }

  void _pipChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PictureInPicture.active.removeListener(_pipChanged);
    _transition.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i == _index) return;
    _transition.duration = motion(context, const Duration(milliseconds: 180));
    _transition.forward(from: 0);
    setState(() {
      _index = i;
      _visited.add(i);
      // Saved-game writes deliberately do not rebuild the whole app on each move.
      // Refresh the home snapshot when returning to it instead.
      if (i == 0) _pages[0] = HomePage(onNavigate: _go);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final size = MediaQuery.sizeOf(context);
    final pip = PictureInPicture.active.value;
    final rail = !pip && size.width >= mobileBreakpoint;
    final expandedRail = size.width >= 1100 && size.height >= 500;
    final short = size.height < 500;
    return ColoredBox(
      color: p.backgroundEnd,
      child: Row(
        children: [
          if (rail)
            Container(
              width: expandedRail ? 184 : 60,
              decoration: BoxDecoration(
                color: p.pane,
                border: Border(right: BorderSide(color: p.border)),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    if (!short)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 24,
                          horizontal: 10,
                        ),
                        child: expandedRail
                            ? Row(
                                children: [
                                  const AppLogo(size: 32),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Chess Coach',
                                      style: TextStyle(
                                        color: p.text,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const AppLogo(size: 32),
                      ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(6),
                        children: [
                          for (var i = 0; i < _labels.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _destination(
                                i,
                                expandedRail: expandedRail,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // This subtree has the same ancestry at every width; games survive resizing.
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: FadeTransition(
                    opacity: _fade,
                    child: IndexedStack(
                      index: _index,
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          TickerMode(
                            enabled: i == _index,
                            child: _visited.contains(i)
                                ? _pages[i]
                                : const SizedBox.shrink(),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!rail && !pip)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: p.glassDecoration(
                      radius: 26,
                      subtle: true,
                      macosElevated: true,
                    ),
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        height: short ? 44 : 60,
                        child: Row(
                          children: [
                            for (var i = 0; i < _labels.length; i++)
                              Expanded(
                                child: _destination(
                                  i,
                                  bottom: true,
                                  short: short,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _destination(
    int i, {
    bool expandedRail = false,
    bool bottom = false,
    bool short = false,
  }) {
    final p = Palette.of(context);
    final selected = i == _index;
    final color = selected ? p.accent : p.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: _labels[i],
      child: Tooltip(
        message: _labels[i],
        child: HoverButton(
          onPressed: () => _go(i),
          builder: (context, states) => Container(
            constraints: BoxConstraints(
              minHeight: bottom ? (short ? 44 : 56) : 44,
            ),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: EdgeInsets.symmetric(
              horizontal: expandedRail ? 12 : 2,
              vertical: 4,
            ),
            decoration: selected
                ? p.glassDecoration(radius: 20, highlight: true, subtle: true)
                : BoxDecoration(
                    color: states.isHovered
                        ? p.glassFillSubtle
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
            child: expandedRail
                ? Row(
                    children: [
                      Icon(_icons[i], size: 21, color: color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _labels[i],
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_icons[i], size: 22, color: color),
                      if (bottom && !short) ...[
                        const SizedBox(height: 3),
                        Text(
                          _labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(fontSize: 11, color: color),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
