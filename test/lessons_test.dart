import 'package:chess_coach/data/curriculum.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/lessons/lesson.dart';
import 'package:chess_coach/lessons/progress.dart';
import 'package:chess_coach/puzzles/puzzle.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lesson content', () {
    test('ids are unique and every lesson has exercises', () {
      final ids = allLessons.map((l) => l.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(allLessons.length, 20);
      for (final l in allLessons) {
        expect(l.steps.where((s) => s.kind == StepKind.find), isNotEmpty, reason: l.id);
      }
    });

    for (final lesson in allLessons) {
      test('${lesson.id}: every move is legal', () {
        for (final (i, step) in lesson.steps.indexed) {
          final reason = '${lesson.id} step ${i + 1}';
          final b = step.resolve();
          expect(b.start.isGameOver, isFalse, reason: reason);
          if (step.kind == StepKind.find) {
            expect(b.solution.length.isOdd, isTrue, reason: '$reason must end with the player\'s move');
            expect(step.demo, isEmpty, reason: reason);
          } else {
            expect(b.solution, isEmpty, reason: reason);
          }
        }
      });
    }

    test('parseMoves reads SAN, UCI, move numbers and castling', () {
      final moves = parseMoves(Chess.initial, '1.e4 e5 2.g1f3 Nc6 3.Bc4 Bc5 4.O-O');
      expect(moves.map((m) => m.$2), ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5', 'O-O']);
      expect(() => parseMoves(Chess.initial, 'e5'), throwsFormatException);
    });

    test('a find step plays like a puzzle, castling included', () async {
      final b = const LessonStep.find('Castle', line: 'e4 e5 Nf3 Nc6 Bc4 Bc5', solution: 'O-O').resolve();
      final session = PuzzleSession(
          PuzzleItem(id: 'x', fen: b.start.fen, moves: b.solution, rating: 800, themes: const [], setup: false),
          moveDelay: Duration.zero);
      await session.start();
      // The board widget sends castling as king-to-g1.
      expect(await session.playerMove(NormalMove(from: Square.e1, to: Square.g1)), isTrue);
      expect(session.state, PuzzleState.solved);
    });
  });

  group('lesson progress', () {
    final lesson = allLessons.first;
    final n = lesson.steps.length;

    test('counts steps, first tries and completion', () async {
      final store = EventStore.memory();
      var progress = LessonProgress.fromEvents(store.events);
      expect(progress.status(lesson), LessonStatus.todo);
      expect(progress.next(), lesson, reason: 'easiest lesson first');

      await store.add(lessonEventType, lessonStepData(lesson, 0));
      await store.add(lessonEventType, lessonStepData(lesson, 1, solved: true));
      await store.add(lessonEventType, lessonStepData(lesson, 3, solved: false));
      progress = LessonProgress.fromEvents(store.events);
      expect(progress.status(lesson), LessonStatus.inProgress);
      expect(progress.fraction(lesson), closeTo(3 / n, 1e-9));
      expect(progress.resumeStep(lesson), 2);
      expect(progress.records[lesson.id]!.found, 1);
      expect(progress.records[lesson.id]!.tried, 2);

      await store.add(lessonEventType, lessonStepData(lesson, n - 1, done: true));
      progress = LessonProgress.fromEvents(store.events);
      expect(progress.status(lesson), LessonStatus.done);
      expect(progress.resumeStep(lesson), 0);
      expect(progress.lessonsDone, 1);
      expect(progress.next(), isNot(lesson));
    });

    test('continues the most recently touched lesson', () async {
      final store = EventStore.memory();
      final a = allLessons[3], b = allLessons[10];
      await store.add(lessonEventType, lessonStepData(a, 0));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.add(lessonEventType, lessonStepData(b, 0));
      expect(LessonProgress.fromEvents(store.events).next(), b);
    });
  });
}
