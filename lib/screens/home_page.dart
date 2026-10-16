import 'package:fluent_ui/fluent_ui.dart';

import '../app/theme.dart';
import '../data/curriculum.dart';
import '../data/event_store.dart';
import '../data/game_record.dart';
import '../data/home_content.dart';
import '../lessons/progress.dart';
import '../train/cards.dart';
import '../train/planner.dart';
import '../train/skill_model.dart';
import '../widgets/common.dart';
import 'cards_page.dart';
import 'lesson_page.dart';
import 'review_page.dart';
import 'session_page.dart';

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
    final store = StoreScope.of(context);
    final lessons = LessonProgress.fromEvents(store.events);
    final next = lessons.next();
    final skills = SkillModel.of(store);
    final due = CardDeck.fromStore(store).due().length;
    final planner = Planner.forStore(store, dueCards: due);

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
                  plan: planner.preview(o.minutes),
                  icon: const [
                    FluentIcons.lightning_bolt,
                    FluentIcons.coffee_script,
                    FluentIcons.game,
                    FluentIcons.trophy2,
                  ][i],
                  onTap: () => startSession(context, o.minutes, onNavigate: onNavigate),
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
        _Stat(
            label: 'Estimated rating',
            value: skills.estimatedRating == null ? 'New' : '~${skills.estimatedRating}',
            note: skills.estimatedRating == null ? 'Play or solve puzzles' : levelName(skills.estimatedRating!),
            icon: FluentIcons.chart),
        _Stat(
            label: 'Training streak',
            value: '${skills.streakDays} day${skills.streakDays == 1 ? '' : 's'}',
            note: skills.activeToday ? 'Trained today' : 'Train today to keep it',
            icon: FluentIcons.favorite_star),
        _Stat(label: 'Target', value: '1800–2000', note: 'Strong club player', icon: FluentIcons.flag),
      ],
    );

    final skillsCard = SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Your skills'),
          for (final area in Area.all) ...[
            Row(children: [
              Expanded(child: Text(Area.label(area), style: TextStyle(color: p.text))),
              Text(skills.rated(area) ? '${skills.areas[area]!.rating.round()}' : 'Not rated yet',
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            Meter(skills.rated(area) ? skills.skill(area) : 0),
            const SizedBox(height: 14),
          ],
          Text('Progress toward your 2000 target. Ratings update after every game, puzzle and lesson.',
              style: TextStyle(color: p.muted, fontSize: 12)),
        ],
      ),
    );

    final reviewCard = SurfaceCard(
      onTap: () => openCardReview(context),
      child: Row(children: [
        Icon(FluentIcons.history, color: due > 0 ? p.accent : p.muted, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(due > 0 ? '$due card${due == 1 ? '' : 's'} to review' : 'No cards due',
                style: TextStyle(fontWeight: FontWeight.w600, color: p.text)),
            Text(
                due > 0
                    ? 'Repertoire moves and old mistakes, just before you forget them'
                    : 'Lessons, reviewed games and missed puzzles add cards here',
                style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
        Icon(FluentIcons.chevron_right, size: 12, color: p.muted),
      ]),
    );

    final active = _ActiveSession(onNavigate: onNavigate);

    final nextFraction = next == null ? 1.0 : lessons.fraction(next);
    final continueCard = SurfaceCard(
      onTap: () => next == null ? onNavigate(3) : openLesson(context, next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Pill(next == null ? 'All lessons done' : (nextFraction > 0 ? 'Continue lesson' : 'Next lesson')),
            const Spacer(),
            Icon(FluentIcons.chevron_right, size: 12, color: p.muted),
          ]),
          const SizedBox(height: 14),
          Text(next?.title ?? 'Every lesson finished',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.text)),
          const SizedBox(height: 4),
          Text(next?.summary ?? 'Repeat any lesson from the Lessons tab, or keep playing and solving puzzles.',
              style: TextStyle(color: p.muted)),
          const SizedBox(height: 16),
          Meter(nextFraction),
          const SizedBox(height: 6),
          Text(
              '${(nextFraction * 100).round()}% complete · '
              '${lessons.lessonsDone} of ${allLessons.length} lessons done',
              style: TextStyle(color: p.muted, fontSize: 12)),
        ],
      ),
    );

    final games = store
        .ofType(GameRecord.eventType)
        .map(GameRecord.fromEvent)
        .toList()
        .reversed
        .take(5)
        .toList();
    final recent = SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Recent games'),
          if (games.isEmpty) ...[
            Text('No games yet. Play the coach and your games appear here for review.',
                style: TextStyle(color: p.muted)),
            const SizedBox(height: 12),
            Button(onPressed: () => onNavigate(1), child: const Text('Play a game')),
          ],
          for (final g in games) _GameRow(game: g),
        ],
      ),
    );

    final tips = tipsByArea[skills.weakestArea]!;
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
                Text(tips[DateTime.now().day % tips.length],
                    style: TextStyle(color: p.muted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );

    return PageFrame(
      title: _greeting(),
      subtitle: skills.hasData ? 'Your coach has today\'s plan ready' : 'Welcome! Pick how much time you have to start',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          active,
          timeCard,
          const SizedBox(height: 16),
          stats,
          const SizedBox(height: 16),
          if (mobile) ...[
            continueCard,
            const SizedBox(height: 16),
            reviewCard,
            const SizedBox(height: 16),
            tip,
            const SizedBox(height: 16),
            recent,
            const SizedBox(height: 16),
            skillsCard,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: [skillsCard, const SizedBox(height: 16), reviewCard])),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(children: [
                    continueCard,
                    const SizedBox(height: 16),
                    tip,
                    const SizedBox(height: 16),
                    recent,
                  ]),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.option, required this.plan, required this.icon, required this.onTap});

  final SessionOption option;
  final String plan;
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
            Text(plan,
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

class _GameRow extends StatelessWidget {
  const _GameRow({required this.game});

  final GameRecord game;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = switch (game.playerScore) {
      1 => p.success,
      0 => p.danger,
      _ => p.muted,
    };
    return HoverButton(
      onPressed: () => openReview(context, game),
      builder: (context, states) => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: states.isHovered ? p.surfaceAlt : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          SizedBox(width: 56, child: Pill(game.outcomeLabel, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'vs Coach ~${game.coachElo} · ${(game.moves.length + 1) ~/ 2} moves · ${game.date.day}/${game.date.month}',
              style: TextStyle(color: p.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('Review', style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w600)),
          Icon(FluentIcons.chevron_right, size: 10, color: p.accent),
        ]),
      ),
    );
  }
}

/// "Continue your session" banner while a planned session is unfinished.
class _ActiveSession extends StatelessWidget {
  const _ActiveSession({required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ValueListenableBuilder<TrainingSession?>(
      valueListenable: TrainingSession.current,
      builder: (context, session, _) {
        if (session == null) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: session,
          builder: (context, _) {
            if (session.finished) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SurfaceCard(
                highlight: true,
                onTap: () => openSession(context, onNavigate: onNavigate),
                child: Row(children: [
                  Icon(FluentIcons.play, color: p.accent, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        'Your ${session.minutes}-minute session: ${session.done.length} of ${session.plan.length} done',
                        style: TextStyle(fontWeight: FontWeight.w600, color: p.text)),
                  ),
                  Text('Continue', style: TextStyle(color: p.accent, fontWeight: FontWeight.w600)),
                  Icon(FluentIcons.chevron_right, size: 10, color: p.accent),
                ]),
              ),
            );
          },
        );
      },
    );
  }
}
