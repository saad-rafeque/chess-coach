/// Course outline from beginner to ~2000. Lesson content lives in `lib/lessons/content/`.
library;

import '../lessons/content/endgames.dart';
import '../lessons/content/middlegame.dart';
import '../lessons/content/openings.dart';
import '../lessons/lesson.dart';

enum Phase { opening, middlegame, endgame }

enum LessonStatus { done, inProgress, todo }

/// Skill areas that lessons, puzzles and games feed (see the skill model).
abstract final class Area {
  static const openings = 'openings';
  static const tactics = 'tactics';
  static const middlegame = 'middlegame';
  static const endgames = 'endgames';

  /// Avoiding blunders in games.
  static const blunders = 'blunders';

  static const all = [tactics, openings, middlegame, endgames, blunders];

  static String label(String area) => switch (area) {
        tactics => 'Tactics',
        openings => 'Openings',
        middlegame => 'Middlegame',
        endgames => 'Endgames',
        blunders => 'Blunder check',
        _ => area,
      };
}

class Lesson {
  const Lesson(this.id, this.title, this.summary, this.level, this.area, this.steps, {this.asBlack = false});

  /// Stable id stored in progress events; never change it.
  final String id;
  final String title;
  final String summary;

  /// Rating band the lesson targets.
  final int level;

  /// Skill area the lesson trains (see [Area]).
  final String area;
  final List<LessonStep> steps;

  /// Show the board from Black's side by default.
  final bool asBlack;
}

class Course {
  const Course(this.phase, this.title, this.subtitle, this.lessons);

  final Phase phase;
  final String title;
  final String subtitle;
  final List<Lesson> lessons;
}

const courses = [
  Course(Phase.opening, 'Openings', 'Your repertoire: Italian Game, 1…e5 and the QGD', openingLessons),
  Course(Phase.middlegame, 'Middlegame', 'Tactics, plans and piece play', middlegameLessons),
  Course(Phase.endgame, 'Endgames', 'Turn advantages into wins', endgameLessons),
];

/// Every lesson, in course order.
List<Lesson> get allLessons => [for (final c in courses) ...c.lessons];

Lesson? lessonById(String id) {
  for (final l in allLessons) {
    if (l.id == id) return l;
  }
  return null;
}
