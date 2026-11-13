import 'package:fluent_ui/fluent_ui.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';

import '../app/board_style.dart';

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

    final timeCard = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How much time do you have?',
          style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in sessionOptions)
              Tooltip(
                message: planner.preview(option.minutes),
                child: Button(
                  onPressed: () => startSession(
                    context,
                    option.minutes,
                    onNavigate: onNavigate,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 8,
                    ),
                    child: Text(option.label),
                  ),
                ),
              ),
          ],
        ),
      ],
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
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(Area.label(area), style: TextStyle(color: p.text)),
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
    final continueCard = _PracticeCard(
      icon: FluentIcons.education,
      eyebrow: next == null
          ? 'All lessons done'
          : (nextFraction > 0 ? 'Continue lesson' : 'Next lesson'),
      title: next?.title ?? 'Keep exploring',
      detail: nextFraction > 0
          ? '${(nextFraction * 100).round()}% complete'
          : 'One idea. A stronger game.',
      onTap: () => next == null ? onNavigate(3) : openLesson(context, next),
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

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: PageFrame(
          title: _greeting(settings.playerName),
          trailing: const SyncChip(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (store.storageError != null) ...[
                CoachBubble(
                  text: store.storageError!,
                  tone: BubbleTone.warning,
                ),
                const SizedBox(height: 12),
              ],
              if (UpdateScope.of(context).available != null) ...[
                const UpdateBanner(),
                const SizedBox(height: 12),
              ],
              _PlayHero(
                onPlay: () => onNavigate(1),
                streakDays: skills.streakDays,
              ),
              const SizedBox(height: 14),
              active,
              ResponsiveGrid(
                minItemWidth: 280,
                spacing: 12,
                children: [
                  _PracticeCard(
                    icon: FluentIcons.puzzle,
                    eyebrow: 'A little challenge',
                    title: 'Puzzle break',
                    detail: 'Find the move. Feel the spark.',
                    onTap: () => onNavigate(2),
                  ),
                  continueCard,
                ],
              ),
              if (due > 0) ...[const SizedBox(height: 12), reviewCard],
              const SizedBox(height: 14),
              _HomeSection(
                title: 'Training options',
                summary: 'A session that fits your time',
                icon: FluentIcons.timer,
                children: [timeCard, tip],
              ),
              const SizedBox(height: 10),
              _HomeSection(
                title: 'Your progress',
                summary:
                    '${skills.gamesPlayed} games · ${lessons.lessonsDone} lessons',
                icon: FluentIcons.chart,
                children: [stats, skillsCard, recent, if (due == 0) reviewCard],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Secondary information stays available without competing with playing.
class _HomeSection extends StatefulWidget {
  const _HomeSection({
    required this.title,
    required this.summary,
    required this.icon,
    required this.children,
  });
  final String title;
  final String summary;
  final IconData icon;
  final List<Widget> children;

  @override
  State<_HomeSection> createState() => _HomeSectionState();
}

class _HomeSectionState extends State<_HomeSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: _expanded,
            child: HoverButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              builder: (context, states) => Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: states.isHovered
                      ? p.accent.withValues(alpha: 0.08)
                      : null,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 20, color: p.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              color: p.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.summary,
                            style: TextStyle(color: p.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _expanded
                          ? FluentIcons.chevron_up
                          : FluentIcons.chevron_down,
                      size: 12,
                      color: p.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < widget.children.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    widget.children[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PracticeCard extends StatelessWidget {
  const _PracticeCard({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.onTap,
  });
  final IconData icon;
  final String eyebrow;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 23, color: p.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow, style: TextStyle(color: p.muted, fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(detail, style: TextStyle(color: p.muted, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(FluentIcons.chevron_right, size: 12, color: p.muted),
        ],
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Pill(game.outcomeLabel, color: color),
                  Text(
                    'Review',
                    style: TextStyle(
                      color: p.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'vs ${SettingsScope.of(context).coachName} ~${game.coachElo} · ${(game.moves.length + 1) ~/ 2} moves · ${game.date.day}/${game.date.month}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.text, fontWeight: FontWeight.w500),
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

/// One primary action and a quiet chess illustration, on phones and desktop.
class _PlayHero extends StatelessWidget {
  const _PlayHero({required this.onPlay, required this.streakDays});
  final VoidCallback onPlay;
  final int streakDays;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = SettingsScope.of(context);
    final style = BoardStyle.of(settings);
    return SurfaceCard(
      highlight: true,
      elevated: true,
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 560;
          final showKnight =
              !wide &&
              c.maxWidth >= 280 &&
              MediaQuery.textScalerOf(context).scale(14) <= 21;
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                streakDays > 0
                    ? '$streakDays day${streakDays == 1 ? '' : 's'} of chess'
                    : 'YOUR NEXT GOOD MOVE',
                style: TextStyle(
                  color: p.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Let’s play\nchess.',
                style: TextStyle(
                  color: p.text,
                  fontSize: wide ? 42 : 32,
                  height: 1.05,
                  letterSpacing: -0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: heading),
                  if (showKnight) ...[
                    const SizedBox(width: 8),
                    ExcludeSemantics(
                      child: Transform.rotate(
                        angle: -0.09,
                        child: Container(
                          width: 92,
                          height: 104,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: p.accent.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Image.asset('assets/pieces/classic/wN.webp'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Your coach. Your pace.',
                style: TextStyle(color: p.muted, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: onPlay,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Text(
                      settings.savedGame == null
                          ? 'Play the coach'
                          : 'Back to your game',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          );
          return Row(
            children: [
              Expanded(child: content),
              if (wide) ...[
                const SizedBox(width: 32),
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: StaticChessboard(
                        size: 228,
                        fen: Chess.initial.fen,
                        orientation: Side.white,
                        settings: style.staticSettings(coordinates: false),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
