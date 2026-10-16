import '../data/curriculum.dart';
import '../data/event_store.dart';
import '../lessons/lesson.dart';
import '../lessons/progress.dart';
import '../puzzles/mistakes.dart';
import '../puzzles/puzzle.dart';
import 'fsrs.dart';
import 'skill_model.dart';

enum CardKind { opening, lesson, mistake, puzzle }

/// A position to remember: a repertoire move, a lesson exercise you missed,
/// a mistake from your games or a puzzle you failed.
class StudyCard {
  const StudyCard({required this.id, required this.kind, required this.title, required this.puzzle});

  final String id;
  final CardKind kind;
  final String title;

  /// The position and solution, played like a puzzle.
  final PuzzleItem puzzle;
}

/// Event data for one card review.
Map<String, dynamic> cardReviewData(StudyCard card, Grade grade) =>
    {'id': card.id, 'kind': card.kind.name, 'grade': grade.value};

/// All study cards with their FSRS memory state, rebuilt from events.
class CardDeck {
  CardDeck._(this.cards, this.states, this._introducedToday);

  factory CardDeck.fromStore(EventStore store, {PuzzleBank? bank, DateTime? now}) {
    final events = store.events;
    final progress = LessonProgress.fromEvents(events);
    final missedSteps = <String>{};
    final failedPuzzles = <String>{};
    for (final e in events) {
      if (e.type == lessonEventType && e.data['solved'] == false) {
        missedSteps.add('lesson:${e.data['lesson']}:${e.data['step']}');
      } else if (e.type == puzzleEventType && e.data['solved'] == false && e.data['rated'] != false) {
        failedPuzzles.add(e.data['id'] as String);
      }
    }

    final cards = <StudyCard>[];
    for (final lesson in allLessons) {
      final record = progress.records[lesson.id];
      if (record == null) continue;
      for (final (i, step) in lesson.steps.indexed) {
        if (step.kind != StepKind.find || !record.steps.contains(i)) continue;
        final id = 'lesson:${lesson.id}:$i';
        final opening = lesson.area == Area.openings;
        if (!opening && !missedSteps.contains(id)) continue;
        try {
          final b = step.resolve();
          cards.add(StudyCard(
            id: id,
            kind: opening ? CardKind.opening : CardKind.lesson,
            title: lesson.title,
            puzzle: PuzzleItem(
                id: id, fen: b.start.fen, moves: b.solution, rating: lesson.level, themes: const [], setup: false),
          ));
        } on FormatException {
          continue;
        }
      }
    }
    for (final p in mistakePuzzles(store)) {
      cards.add(StudyCard(id: p.id, kind: CardKind.mistake, title: 'A mistake from your game', puzzle: p));
    }
    final b = bank ?? PuzzleBank.loaded;
    if (b != null) {
      for (final id in failedPuzzles) {
        final p = b.byId[id];
        if (p != null) cards.add(StudyCard(id: id, kind: CardKind.puzzle, title: 'A puzzle you missed', puzzle: p));
      }
    }

    const fsrs = Fsrs();
    final states = <String, CardState>{};
    final today = now ?? DateTime.now();
    var introduced = 0;
    for (final e in events) {
      if (e.type != cardEventType) continue;
      final id = e.data['id'] as String;
      final g = Grade.values.firstWhere((g) => g.value == e.data['grade'], orElse: () => Grade.good);
      final t = e.time.toLocal();
      if (!states.containsKey(id) && t.year == today.year && t.month == today.month && t.day == today.day) {
        introduced++;
      }
      states[id] = fsrs.review(states[id], g, e.time);
    }
    return CardDeck._(cards, states, introduced);
  }

  final List<StudyCard> cards;
  final Map<String, CardState> states;
  final int _introducedToday;

  /// New cards shown per day, so the review pile stays small.
  static const newPerDay = 10;

  /// Cards to study now: reviews that are due (most overdue first), then a few new cards.
  List<StudyCard> due({DateTime? now}) {
    final t = now ?? DateTime.now();
    final reviews = [
      for (final c in cards)
        if (states[c.id]?.isDue(t) ?? false) c,
    ]..sort((a, b) => states[a.id]!.due.compareTo(states[b.id]!.due));
    final fresh = [
      for (final c in cards)
        if (!states.containsKey(c.id)) c,
    ];
    final allowed = (newPerDay - _introducedToday).clamp(0, newPerDay);
    // Your own mistakes first, then repertoire, then the rest.
    fresh.sort((a, b) => a.kind.index == b.kind.index ? 0 : (_order(a.kind) - _order(b.kind)));
    return [...reviews, ...fresh.take(allowed)];
  }

  static int _order(CardKind k) => switch (k) {
        CardKind.mistake => 0,
        CardKind.opening => 1,
        CardKind.lesson => 2,
        CardKind.puzzle => 3,
      };
}
