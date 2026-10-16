import 'package:fluent_ui/fluent_ui.dart';

import '../app/theme.dart';
import '../data/curriculum.dart';
import '../data/sample_profile.dart';
import '../widgets/common.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onNavigate});

  /// Switches to another tab: 1 Play, 2 Puzzles, 3 Lessons.
  final ValueChanged<int> onNavigate;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final mobile = isMobile(context);
    final next = courses.first.lessons.firstWhere((l) => l.status == LessonStatus.inProgress);

    final timeCard = SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(FluentIcons.timer, color: p.accent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('How much time do you have?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: p.text)),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Your coach builds the best session for the time you have.',
              style: TextStyle(color: p.muted)),
          const SizedBox(height: 16),
          ResponsiveGrid(
            minItemWidth: mobile ? 140 : 170,
            spacing: 12,
            children: [
              for (final (i, o) in sessionOptions.indexed)
                _SessionTile(
                  option: o,
                  icon: const [
                    FluentIcons.lightning_bolt,
                    FluentIcons.coffee_script,
                    FluentIcons.game,
                    FluentIcons.trophy2,
                  ][i],
                  onTap: () => onNavigate(o.minutes <= 15 ? 2 : (o.minutes <= 60 ? 1 : 3)),
                ),
            ],
          ),
        ],
      ),
    );

    final stats = ResponsiveGrid(
      minItemWidth: mobile ? 140 : 200,
      spacing: 12,
      children: [
        _Stat(label: 'Estimated rating', value: '~$sampleRating', note: 'Beginner', icon: FluentIcons.chart),
        _Stat(label: 'Puzzle streak', value: '$samplePuzzleStreak days', note: 'Keep it going', icon: FluentIcons.favorite_star),
        _Stat(label: 'Target', value: '1800–2000', note: 'Strong club player', icon: FluentIcons.flag),
      ],
    );

    final skills = SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Your skills'),
          for (final s in sampleSkills) ...[
            Row(children: [
              Expanded(child: Text(s.name, style: TextStyle(color: p.text))),
              Text('${(s.value * 100).round()}%', style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            Meter(s.value),
            const SizedBox(height: 14),
          ],
          Text('Progress toward your 2000 target', style: TextStyle(color: p.muted, fontSize: 12)),
        ],
      ),
    );

    final continueCard = SurfaceCard(
      onTap: () => onNavigate(3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Pill('Continue'),
            const Spacer(),
            Icon(FluentIcons.chevron_right, size: 12, color: p.muted),
          ]),
          const SizedBox(height: 14),
          Text(next.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.text)),
          const SizedBox(height: 4),
          Text(next.summary, style: TextStyle(color: p.muted)),
          const SizedBox(height: 16),
          Meter(next.progress),
          const SizedBox(height: 6),
          Text('${(next.progress * 100).round()}% complete', style: TextStyle(color: p.muted, fontSize: 12)),
        ],
      ),
    );

    final tip = SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(FluentIcons.lightbulb, color: p.accent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Coach tip', style: TextStyle(fontWeight: FontWeight.w600, color: p.text)),
                const SizedBox(height: 4),
                Text(tipsOfTheDay[DateTime.now().day % tipsOfTheDay.length],
                    style: TextStyle(color: p.muted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );

    return PageFrame(
      title: _greeting(),
      subtitle: 'Your coach has today\'s plan ready',
      trailing: mobile ? null : Pill('Preview data', color: p.warning),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          timeCard,
          const SizedBox(height: 16),
          stats,
          const SizedBox(height: 16),
          if (mobile) ...[
            continueCard,
            const SizedBox(height: 16),
            tip,
            const SizedBox(height: 16),
            skills,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: skills),
                const SizedBox(width: 16),
                Expanded(child: Column(children: [continueCard, const SizedBox(height: 16), tip])),
              ],
            ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.option, required this.icon, required this.onTap});

  final SessionOption option;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return HoverButton(
      onPressed: onTap,
      builder: (context, states) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: 118,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: states.isHovered ? p.accent.withValues(alpha: 0.12) : p.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: states.isHovered ? p.accent : p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: p.accent, size: 18),
            const Spacer(),
            Text(option.label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 2),
            Text(option.plan,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.muted, height: 1.3)),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.note, required this.icon});

  final String label;
  final String value;
  final String note;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(icon, color: p.accent, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: p.muted, fontSize: 12)),
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text)),
                Text(note, style: TextStyle(color: p.muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
