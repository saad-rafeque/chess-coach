import 'package:fluent_ui/fluent_ui.dart';

import '../app/theme.dart';
import '../data/curriculum.dart';
import '../data/event_store.dart';
import '../data/game_record.dart';
import '../lessons/progress.dart';
import '../puzzles/puzzle.dart';
import '../train/cards.dart';
import '../train/planner.dart';
import '../train/skill_model.dart';
import '../widgets/board_layout.dart';
import '../widgets/common.dart';
import 'cards_page.dart';
import 'lesson_page.dart';
import 'puzzles_page.dart';

/// A planned training session and how far the player got. Kept in memory while
/// the app runs, so the player can leave for a game and come back.
class TrainingSession extends ChangeNotifier {
  TrainingSession(this.minutes, this.plan);

  /// The session in progress, if any.
  static final current = ValueNotifier<TrainingSession?>(null);

  final int minutes;
  final List<Activity> plan;

  /// Existing event IDs at the start of each block. Sync may insert older
  /// events into the middle of the log, so list offsets cannot mark progress.
  final started = <int, Set<String>>{};
  final _startedAt = <int, DateTime>{};
  final done = <int>{};

  bool get finished => done.length == plan.length;
  int? get nextBlock {
    for (var i = 0; i < plan.length; i++) {
      if (!done.contains(i)) return i;
    }
    return null;
  }

  void skip(int block) {
    done.add(block);
    notifyListeners();
  }

  /// Resuming a block keeps the original baseline and completed work.
  void begin(int block, EventStore store) {
    started.putIfAbsent(block, () => {for (final e in store.events) e.id});
    _startedAt.putIfAbsent(block, () => DateTime.now().toUtc());
  }

  List<AppEvent> _fresh(int block, List<AppEvent> events) {
    final baseline = started[block];
    final since = _startedAt[block];
    if (baseline == null || since == null) return const [];
    return events
        .where((e) => !baseline.contains(e.id) && !e.time.isBefore(since))
        .toList();
  }

  Iterable<AppEvent> _puzzleAttempts(Activity a, Iterable<AppEvent> events) =>
      events.where(
        (e) =>
            e.type == puzzleEventType &&
            e.data['rated'] != false &&
            (a.theme == null ||
                ((e.data['themes'] as List?) ?? const []).contains(a.theme)),
      );

  /// How many puzzles or review cards still belong to this block.
  int remaining(int block, EventStore store) {
    final a = plan[block];
    final fresh = _fresh(block, store.events);
    final completed = a.kind == ActivityKind.review
        ? fresh.where((e) => e.type == cardEventType).length
        : _puzzleAttempts(a, fresh).length;
    return (a.count - completed).clamp(0, a.count);
  }

  /// Marks started blocks as done once the events show the work, and stores the
  /// bandit reward for each. Returns true if anything changed.
  bool refresh(EventStore store) {
    final events = store.events;
    var changed = false;
    for (final i in started.keys) {
      if (done.contains(i)) continue;
      final a = plan[i];
      final fresh = _fresh(i, events);
      final freshIds = fresh.map((e) => e.id).toSet();
      final before = events.where((e) => !freshIds.contains(e.id));
      final reward = _reward(a, events, before, fresh);
      if (reward == null) continue;
      done.add(i);
      changed = true;
      store.add(activityEventType, activityData(a, reward));
    }
    if (changed) notifyListeners();
    return changed;
  }

  /// Null while the block isn't finished; otherwise 0..1.
  double? _reward(
    Activity a,
    List<AppEvent> all,
    Iterable<AppEvent> before,
    List<AppEvent> fresh,
  ) {
    double gain(String area, Iterable<AppEvent> before) {
      final was = SkillModel.fromEvents(before).areas[area]?.rating ?? 900.0;
      final now = SkillModel.fromEvents(all).areas[area]?.rating ?? 900.0;
      return (0.5 + (now - was) / 100).clamp(0, 1);
    }

    switch (a.kind) {
      case ActivityKind.puzzles ||
          ActivityKind.themePuzzles ||
          ActivityKind.endgame:
        final tries = _puzzleAttempts(a, fresh).length;
        return tries >= a.count ? gain(a.area, before) : null;
      case ActivityKind.review:
        final grades = [
          for (final e in fresh)
            if (e.type == cardEventType) e.data['grade'] as int,
        ];
        if (grades.length < a.count) return null;
        return grades.where((g) => g >= 3).length / grades.length;
      case ActivityKind.lesson:
        final steps = fresh
            .where(
              (e) =>
                  e.type == lessonEventType && e.data['lesson'] == a.lesson!.id,
            )
            .toList();
        final finished =
            steps.any((e) => e.data['done'] == true) || steps.length >= 4;
        if (!finished) return null;
        final tries = steps.where((e) => e.data['solved'] is bool).toList();
        return tries.isEmpty
            ? 0.5
            : tries.where((e) => e.data['solved'] == true).length /
                  tries.length;
      case ActivityKind.game:
        if (!fresh.any((e) => e.type == GameRecord.eventType)) return null;
        final was = SkillModel.fromEvents(before).games.rating;
        final now = SkillModel.fromEvents(all).games.rating;
        return (0.5 + (now - was) / 100).clamp(0, 1);
    }
  }
}

/// Plans a session for [minutes] and opens it.
Future<void> startSession(
  BuildContext context,
  int minutes, {
  required ValueChanged<int> onNavigate,
}) {
  final store = StoreScope.read(context);
  final due = CardDeck.of(store).due().length;
  final plan = Planner.forStore(store, dueCards: due).plan(minutes);
  TrainingSession.current.value = TrainingSession(minutes, plan);
  return openSession(context, onNavigate: onNavigate);
}

Future<void> openSession(
  BuildContext context, {
  required ValueChanged<int> onNavigate,
}) => Navigator.of(
  context,
).push(FluentPageRoute(builder: (_) => SessionPage(onNavigate: onNavigate)));

class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.onNavigate});

  /// Switches the main tab (1 = Play) for blocks that happen there.
  final ValueChanged<int> onNavigate;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    final s = TrainingSession.current.value;
    if (s != null)
      WidgetsBinding.instance.addPostFrameCallback((_) => s.refresh(store));
  }

  Future<void> _start(TrainingSession s, int i) async {
    final store = StoreScope.read(context);
    final a = s.plan[i];
    s.begin(i, store);
    s.refresh(store);
    if (s.done.contains(i)) return;
    switch (a.kind) {
      case ActivityKind.puzzles:
        await openPuzzleDrill(context, goal: s.remaining(i, store));
      case ActivityKind.themePuzzles || ActivityKind.endgame:
        await openPuzzleDrill(
          context,
          goal: s.remaining(i, store),
          theme: a.theme,
        );
      case ActivityKind.review:
        await openCardReview(context, limit: s.remaining(i, store));
      case ActivityKind.lesson:
        await openLesson(context, a.lesson!);
      case ActivityKind.game:
        Navigator.of(context).pop();
        widget.onNavigate(1);
        return;
    }
    if (mounted) s.refresh(store);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = TrainingSession.current.value;
    return PageFrame(
      title: s == null ? 'Training session' : '${s.minutes}-minute session',
      subtitle: 'Planned by your coach for what helps you most right now',
      leading: const PageBackButton(),
      child: s == null
          ? const CoachBubble(
              text: 'No session planned. Pick how much time you have on Home.',
            )
          : ListenableBuilder(
              listenable: s,
              builder: (context, _) => _plan(p, s),
            ),
    );
  }

  Widget _plan(Palette p, TrainingSession s) {
    final skills = SkillModel.of(StoreScope.of(context));
    final next = s.nextBlock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.finished
                          ? 'Session complete. Well done!'
                          : '${s.done.length} of ${s.plan.length} done',
                      style: TextStyle(
                        color: p.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (s.finished)
                    FilledButton(
                      onPressed: () {
                        TrainingSession.current.value = null;
                        Navigator.of(context).maybePop();
                      },
                      child: const Text('Finish'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Meter(
                s.plan.isEmpty ? 1 : s.done.length / s.plan.length,
                color: s.finished ? p.success : null,
              ),
              const SizedBox(height: 10),
              Text(
                !skills.hasData
                    ? 'Your coach is still getting to know you. Every puzzle, lesson and game sharpens the plan.'
                    : skills.rated(skills.weakestArea)
                    ? 'Focus: ${Area.label(skills.weakestArea).toLowerCase()} is your weakest area right now.'
                    : 'Your coach hasn\'t seen your ${Area.label(skills.weakestArea).toLowerCase()} yet, so it '
                          'gets extra attention.',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final (i, a) in s.plan.indexed) ...[
          _BlockRow(
            activity: a,
            done: s.done.contains(i),
            current: i == next,
            started: s.started.containsKey(i),
            onStart: () => _start(s, i),
            onSkip: () => s.skip(i),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({
    required this.activity,
    required this.done,
    required this.current,
    required this.started,
    required this.onStart,
    required this.onSkip,
  });

  final Activity activity;
  final bool done;
  final bool current;
  final bool started;
  final VoidCallback onStart;
  final VoidCallback onSkip;

  IconData get _icon => switch (activity.kind) {
    ActivityKind.puzzles => FluentIcons.lightning_bolt,
    ActivityKind.themePuzzles => FluentIcons.puzzle,
    ActivityKind.review => FluentIcons.history,
    ActivityKind.lesson => FluentIcons.education,
    ActivityKind.endgame => FluentIcons.flag,
    ActivityKind.game => FluentIcons.game,
  };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SurfaceCard(
      highlight: current,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (done ? p.success : p.accent).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              done ? FluentIcons.check_mark : _icon,
              color: done ? p.success : p.accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  style: TextStyle(
                    color: done ? p.muted : p.text,
                    fontWeight: FontWeight.w600,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  '${activity.detail} · ~${activity.minutes} min',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!done) ...[
            const SizedBox(width: 8),
            if (current)
              FilledButton(
                onPressed: onStart,
                child: Text(started ? 'Continue' : 'Start'),
              )
            else
              Button(onPressed: onStart, child: const Text('Start')),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Skip',
              child: IconButton(
                icon: Icon(FluentIcons.cancel, size: 12, color: p.muted),
                onPressed: onSkip,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
