/// Course outline from beginner to ~2000. Lesson content arrives in milestone 4;
/// for now this drives the Lessons screen.
library;

enum Phase { opening, middlegame, endgame }

enum LessonStatus { done, inProgress, todo }

class Lesson {
  const Lesson(this.title, this.summary, this.level,
      {this.status = LessonStatus.todo, this.progress = 0});

  final String title;
  final String summary;

  /// Rating band the lesson targets.
  final int level;
  final LessonStatus status;
  final double progress;
}

class Course {
  const Course(this.phase, this.title, this.subtitle, this.lessons);

  final Phase phase;
  final String title;
  final String subtitle;
  final List<Lesson> lessons;

  double get progress {
    final total = lessons.fold<double>(0, (sum, l) {
      return sum + (l.status == LessonStatus.done ? 1 : l.progress);
    });
    return total / lessons.length;
  }
}

const courses = [
  Course(Phase.opening, 'Openings', 'Your repertoire: Italian Game, 1…e5 and the QGD', [
    Lesson('Opening principles', 'Control the centre, develop pieces, castle early.', 800,
        status: LessonStatus.done),
    Lesson('Italian Game basics', 'Your first White opening: 1.e4 e5 2.Nf3 Nc6 3.Bc4.', 900,
        status: LessonStatus.inProgress, progress: 0.4),
    Lesson('Opening traps to avoid', 'Scholar\'s mate, Fried Liver and other early knockouts.', 1000),
    Lesson('Meeting 1.e4 with 1…e5', 'Solid, classical answers as Black.', 1000),
    Lesson('Queen\'s Gambit Declined', 'A rock-solid defence against 1.d4.', 1100),
    Lesson('Italian middlegame plans', 'c3, d4 and the slow Giuoco Pianissimo.', 1400),
    Lesson('Deeper repertoire lines', 'Sidelines and move orders at club level.', 1700),
  ]),
  Course(Phase.middlegame, 'Middlegame', 'Tactics, plans and piece play', [
    Lesson('Blunder check', 'Before every move: checks, captures, threats.', 800,
        status: LessonStatus.done),
    Lesson('Forks, pins and skewers', 'The three tactics that win most games.', 900,
        status: LessonStatus.inProgress, progress: 0.2),
    Lesson('Discovered attacks', 'Move one piece, attack with another.', 1100),
    Lesson('Pawn structure basics', 'Isolated, doubled and passed pawns.', 1300),
    Lesson('Good and bad pieces', 'Improve your worst piece.', 1400),
    Lesson('Attacking the castled king', 'Sacrifices and pawn storms.', 1600),
    Lesson('Making a plan', 'Find targets and build a strategy.', 1800),
  ]),
  Course(Phase.endgame, 'Endgames', 'Turn advantages into wins', [
    Lesson('Mate with queen and rook', 'The essential checkmates.', 800,
        status: LessonStatus.done),
    Lesson('King and pawn: opposition', 'The key idea in pawn endings.', 1000),
    Lesson('The square of the pawn', 'Can the king catch it?', 1000),
    Lesson('Rook endings: Lucena and Philidor', 'The two positions every player must know.', 1500),
    Lesson('Bishop versus knight', 'Which minor piece wins, and when.', 1700),
    Lesson('Converting an advantage', 'Win "won" positions without stress.', 1900),
  ]),
];
