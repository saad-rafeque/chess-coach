import 'package:fluent_ui/fluent_ui.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';

import '../app/board_style.dart';
import '../puzzles/puzzle.dart';

import '../app/settings.dart';
import '../app/theme.dart';
import '../data/curriculum.dart';
import '../data/event_store.dart';
import '../data/game_record.dart';
import '../data/home_content.dart';
import '../lessons/progress.dart';
import '../train/cards.dart';
import '../train/planner.dart';
import '../train/skill_model.dart';
import '../widgets/board_layout.dart';
import '../widgets/common.dart';
import '../widgets/sync_settings.dart';
import '../widgets/update_ui.dart';
import 'cards_page.dart';
import 'lesson_page.dart';
import 'review_page.dart';
import 'session_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onNavigate});

  /// Switches to another tab: 1 Play, 2 Puzzles, 3 Lessons.
  final ValueChanged<int> onNavigate;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  ValueChanged<int> get onNavigate => widget.onNavigate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _greeting(String name) {
    final h = DateTime.now().hour;
    final hello = h < 12
        ? 'Good morning'
        : (h < 17 ? 'Good afternoon' : 'Good evening');
    return name.isEmpty ? hello : '$hello, $name';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final mobile = isMobile(context);
    final store = StoreScope.of(context);
    final lessons = LessonProgress.fromEvents(store.events);
    final next = lessons.next();
    final skills = SkillModel.of(store);
    final settings = SettingsScope.of(context);
    final due = CardDeck.of(store).due().length;
    final planner = Planner.forStore(store, dueCards: due);

    final timeCard = SurfaceCard(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      p.accent.withValues(alpha: 0.24),
                      p.accent.withValues(alpha: 0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.accent.withValues(alpha: 0.3)),
                ),
                child: Icon(FluentIcons.timer, color: p.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How much time do you have?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: p.text,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your coach builds the best session for the time you have.',
                      style: TextStyle(color: p.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
                  ][i % 4],
                  onTap: () =>
                      startSession(context, o.minutes, onNavigate: onNavigate),
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
          value: skills.estimatedRating == null
              ? 'New'
              : '~${skills.estimatedRating}',
          note: skills.estimatedRating == null
              ? 'Play or solve puzzles'
              : levelName(skills.estimatedRating!),
          icon: FluentIcons.chart,
        ),
        _Stat(
          label: 'Training streak',
          value: '${skills.streakDays} day${skills.streakDays == 1 ? '' : 's'}',
          note: skills.activeToday ? 'Nice work today' : 'One small step today',
          icon: FluentIcons.favorite_star,
        ),
        _Stat(
          label: 'Games played',
          value: '${skills.gamesPlayed}',
          note: 'Every game teaches you',
          icon: FluentIcons.game,
        ),
      ],
    );

    final skillsCard = SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Your skills'),
          for (final area in Area.all) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    Area.label(area),
                    style: TextStyle(color: p.text),
                  ),
                ),
                Text(
                  skills.rated(area) && skills.areas[area] != null
                      ? '${skills.areas[area]!.rating.round()}'
                      : 'Not rated yet',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Meter(skills.rated(area) ? skills.skill(area) : 0),
            const SizedBox(height: 14),
          ],
          Text(
            'Your skills grow with each game, puzzle and lesson. Unrated areas need a little more practice.',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
        ],
      ),
    );

    final reviewCard = SurfaceCard(
      onTap: () => openCardReview(context),
      child: Row(
        children: [
          Icon(
            FluentIcons.history,
            color: due > 0 ? p.accent : p.muted,
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  due > 0
                      ? '$due card${due == 1 ? '' : 's'} to review'
                      : 'No cards due',
                  style: TextStyle(fontWeight: FontWeight.w600, color: p.text),
                ),
                Text(
                  due > 0
                      ? 'Repertoire moves and old mistakes, just before you forget them'
                      : 'Lessons, reviewed games and missed puzzles add cards here',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(FluentIcons.chevron_right, size: 12, color: p.muted),
        ],
      ),
    );

    final active = _ActiveSession(onNavigate: onNavigate);

    final nextFraction = next == null ? 1.0 : lessons.fraction(next);
    final continueCard = SurfaceCard(
      onTap: () => next == null ? onNavigate(3) : openLesson(context, next),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill(
                next == null
                    ? 'All lessons done'
                    : (nextFraction > 0 ? 'Continue lesson' : 'Next lesson'),
              ),
              const Spacer(),
              Icon(FluentIcons.chevron_right, size: 12, color: p.muted),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            next?.title ?? 'Every lesson finished',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: p.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            next?.summary ??
                'Repeat any lesson from the Lessons tab, or keep playing and solving puzzles.',
            style: TextStyle(color: p.muted),
          ),
          const SizedBox(height: 16),
          Meter(nextFraction),
          const SizedBox(height: 6),
          Text(
            '${(nextFraction * 100).round()}% complete · '
            '${lessons.lessonsDone} of ${allLessons.length} lessons done',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
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
            Text(
              'No games yet. Play the coach and your games appear here for review.',
              style: TextStyle(color: p.muted),
            ),
            const SizedBox(height: 12),
            Button(
              onPressed: () => onNavigate(1),
              child: const Text('Play a game'),
            ),
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
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(FluentIcons.lightbulb, color: p.accent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tip from ${settings.coachName}',
                  style: TextStyle(fontWeight: FontWeight.w600, color: p.text),
                ),
                const SizedBox(height: 4),
                Text(
                  tips[DateTime.now().day % tips.length],
                  style: TextStyle(color: p.muted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return PageFrame(
      title: _greeting(settings.playerName),
      subtitle: 'A little chess. A little better, every day.',
      trailing: const SyncChip(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (store.storageError != null) ...[
            CoachBubble(text: store.storageError!, tone: BubbleTone.warning),
            const SizedBox(height: 8),
          ],
          if (UpdateScope.of(context).available != null) ...[
            const UpdateBanner(),
            const SizedBox(height: 8),
          ],
          _PlayHero(
            onPlay: () => onNavigate(1),
            onPuzzles: () => onNavigate(2),
          ),
          const SizedBox(height: 16),
          active,
          _DailyPractice(onNavigate: onNavigate),
          const SizedBox(height: 16),
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
                Expanded(
                  child: Column(
                    children: [
                      skillsCard,
                      const SizedBox(height: 16),
                      reviewCard,
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      continueCard,
                      const SizedBox(height: 16),
                      tip,
                      const SizedBox(height: 16),
                      recent,
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.option,
    required this.plan,
    required this.icon,
    required this.onTap,
  });

  final SessionOption option;
  final String plan;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return HoverButton(
      onPressed: onTap,
      builder: (context, states) => AnimatedScale(
        duration: motion(context, const Duration(milliseconds: 140)),
        curve: Curves.easeOutCubic,
        scale: states.isPressed ? 0.985 : 1.0,
        child: AnimatedContainer(
          duration: motion(context, const Duration(milliseconds: 140)),
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: states.isHovered
                ? p.accent.withValues(alpha: 0.16)
                : p.glassFillSubtle,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: states.isHovered ? p.accent : p.glassBorderSubtle,
              width: states.isHovered ? 1.5 : 1.0,
            ),
            boxShadow: [
              if (states.isHovered)
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.20),
                  blurRadius: 16,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      p.accent.withValues(
                        alpha: states.isHovered ? 0.35 : 0.20,
                      ),
                      p.accent.withValues(
                        alpha: states.isHovered ? 0.20 : 0.10,
                      ),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: p.accent.withValues(
                      alpha: states.isHovered ? 0.5 : 0.25,
                    ),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: p.accent, size: 17),
              ),
              const SizedBox(height: 12),
              Text(
                option.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 2),
              // Two lines tall whatever the plan, so the tiles line up.
              SizedBox(
                height:
                    MediaQuery.textScalerOf(context).scale(12) * 1.3 * 2 + 2,
                child: Text(
                  plan,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.muted, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
  });

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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.accent.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: p.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: p.muted, fontSize: 12)),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: p.text,
                  ),
                ),
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
      builder: (context, states) => AnimatedScale(
        duration: motion(context, const Duration(milliseconds: 120)),
        curve: Curves.easeOutCubic,
        scale: states.isPressed ? 0.98 : (states.isHovered ? 1.01 : 1.0),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: states.isHovered
                ? p.accent.withValues(alpha: 0.12)
                : p.glassFillSubtle,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: states.isHovered
                  ? p.accent.withValues(alpha: 0.3)
                  : p.glassBorderSubtle,
            ),
          ),
          child: Row(
            children: [
              SizedBox(width: 56, child: Pill(game.outcomeLabel, color: color)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'vs ${SettingsScope.of(context).coachName} ~${game.coachElo} · ${(game.moves.length + 1) ~/ 2} moves · ${game.date.day}/${game.date.month}',
                  style: TextStyle(color: p.text, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Review',
                      style: TextStyle(
                        color: p.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(FluentIcons.chevron_right, size: 9, color: p.accent),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                child: Row(
                  children: [
                    Icon(FluentIcons.play, color: p.accent, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your ${session.minutes}-minute session: ${session.done.length} of ${session.plan.length} done',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: p.text,
                        ),
                      ),
                    ),
                    Text(
                      'Continue',
                      style: TextStyle(
                        color: p.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(FluentIcons.chevron_right, size: 10, color: p.accent),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// A clear first action, with a real board preview instead of decorative clutter.
class _PlayHero extends StatelessWidget {
  const _PlayHero({required this.onPlay, required this.onPuzzles});
  final VoidCallback onPlay;
  final VoidCallback onPuzzles;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = SettingsScope.of(context);
    final style = BoardStyle.of(settings);
    return SurfaceCard(
      highlight: true,
      elevated: true,
      child: LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR NEXT GOOD MOVE',
                    style: TextStyle(
                      color: p.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Let’s play chess.',
                    style: TextStyle(
                      color: p.text,
                      fontSize: c.maxWidth < 400 ? 27 : 36,
                      height: 1.1,
                      letterSpacing: -0.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A worthy opponent. A coach in your corner.',
                    style: TextStyle(color: p.muted, fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton(
                        onPressed: onPlay,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            settings.savedGame == null
                                ? 'Play the coach'
                                : 'Back to your game',
                          ),
                        ),
                      ),
                      Button(
                        onPressed: onPuzzles,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Text('Solve puzzles'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (c.maxWidth >= 560) ...[
              const SizedBox(width: 32),
              Semantics(
                button: true,
                label: 'Play the coach',
                child: GestureDetector(
                  onTap: onPlay,
                  child: IgnorePointer(
                    child: StaticChessboard(
                      size: 180,
                      fen: Chess.initial.fen,
                      orientation: Side.white,
                      settings: style.staticSettings(coordinates: false),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Optional daily practice uses real local activity and never locks a feature.
class _DailyPractice extends StatelessWidget {
  const _DailyPractice({required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final now = DateTime.now();
    final events = StoreScope.of(context).events.where((e) {
      final t = e.time.toLocal();
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }).toList();
    final puzzles = events
        .where((e) => e.type == puzzleEventType && e.data['solved'] == true)
        .length;
    final played = events.any((e) => e.type == GameRecord.eventType);
    final learned = events.any(
      (e) => e.type == lessonEventType || e.type == cardEventType,
    );
    final done = (played ? 1 : 0) + (puzzles >= 3 ? 1 : 0) + (learned ? 1 : 0);
    final tasks = [
      (
        label: 'Play a game',
        detail: played ? 'Completed' : 'Learn by playing',
        complete: played,
        tab: 1,
        icon: FluentIcons.game,
      ),
      (
        label: 'Solve 3 puzzles',
        detail: '${puzzles.clamp(0, 3)} / 3 solved',
        complete: puzzles >= 3,
        tab: 2,
        icon: FluentIcons.puzzle,
      ),
      (
        label: 'Learn something',
        detail: learned ? 'Completed' : 'Try a lesson or review',
        complete: learned,
        tab: 3,
        icon: FluentIcons.education,
      ),
    ];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  done == 3 ? 'A good day for chess' : 'Your daily three',
                  style: TextStyle(
                    color: p.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$done / 3',
                style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            done == 3
                ? 'Nicely done. Play on, or come back refreshed tomorrow.'
                : 'A small, balanced practice. Go at your own pace.',
            style: TextStyle(color: p.muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Meter(done / 3, height: 5),
          const SizedBox(height: 12),
          ResponsiveGrid(
            minItemWidth: 180,
            spacing: 8,
            children: [
              for (final task in tasks)
                HoverButton(
                  onPressed: () => onNavigate(task.tab),
                  builder: (context, states) => Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: states.isHovered
                          ? p.accent.withValues(alpha: 0.12)
                          : p.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          task.complete ? FluentIcons.check_mark : task.icon,
                          color: p.accent,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.label,
                                style: TextStyle(
                                  color: p.text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                task.detail,
                                style: TextStyle(color: p.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          FluentIcons.chevron_right,
                          size: 10,
                          color: p.muted,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
