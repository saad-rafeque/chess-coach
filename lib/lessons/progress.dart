import '../data/curriculum.dart';
import '../data/event_store.dart';

const lessonEventType = 'lesson';

/// Event data for a completed lesson step.
Map<String, dynamic> lessonStepData(Lesson lesson, int step, {bool? solved, bool done = false}) => {
      'lesson': lesson.id,
      'step': step,
      'steps': lesson.steps.length,
      'area': lesson.area,
      'level': lesson.level,
      'solved': ?solved,
      if (done) 'done': true,
    };

/// What the player has done in one lesson.
class LessonRecord {
  final steps = <int>{};
  bool done = false;
  DateTime? last;

  /// "Find the move" steps answered right / tried, first attempts only.
  int found = 0;
  int tried = 0;
}

/// Lesson progress derived from the stored lesson events.
class LessonProgress {
  LessonProgress._(this.records);

  factory LessonProgress.fromEvents(Iterable<AppEvent> events) {
    final records = <String, LessonRecord>{};
    for (final e in events) {
      if (e.type != lessonEventType) continue;
      final id = e.data['lesson'] as String?;
      final step = e.data['step'] as int?;
      if (id == null || step == null) continue;
      final r = records.putIfAbsent(id, LessonRecord.new);
      r.steps.add(step);
      if (e.data['done'] == true) r.done = true;
      r.last = e.time;
      final solved = e.data['solved'];
      if (solved is bool) {
        r.tried++;
        if (solved) r.found++;
      }
    }
    return LessonProgress._(records);
  }

  final Map<String, LessonRecord> records;

  /// 0..1 share of the lesson completed.
  double fraction(Lesson l) {
    final r = records[l.id];
    if (r == null) return 0;
    if (r.done) return 1;
    final n = l.steps.length;
    return n == 0 ? 0 : r.steps.where((s) => s < n).length / n;
  }

  LessonStatus status(Lesson l) {
    final f = fraction(l);
    if (f >= 1) return LessonStatus.done;
    return f > 0 ? LessonStatus.inProgress : LessonStatus.todo;
  }

  double courseFraction(Course c) =>
      c.lessons.isEmpty ? 0 : c.lessons.fold<double>(0, (s, l) => s + fraction(l)) / c.lessons.length;

  int get lessonsDone => allLessons.where((l) => status(l) == LessonStatus.done).length;

  /// First step not done yet (0 if the lesson is finished or new).
  int resumeStep(Lesson l) {
    final r = records[l.id];
    if (r == null || r.done) return 0;
    for (var i = 0; i < l.steps.length; i++) {
      if (!r.steps.contains(i)) return i;
    }
    return 0;
  }

  /// The lesson to continue: the most recently touched unfinished one, otherwise
  /// the easiest lesson not started yet. Null when everything is done.
  Lesson? next() {
    Lesson? best;
    DateTime? bestTime;
    for (final l in allLessons) {
      final r = records[l.id];
      if (r == null || status(l) != LessonStatus.inProgress) continue;
      if (bestTime == null || r.last!.isAfter(bestTime)) {
        best = l;
        bestTime = r.last;
      }
    }
    if (best != null) return best;
    final todo = allLessons.where((l) => status(l) == LessonStatus.todo).toList();
    if (todo.isEmpty) return null;
    // Stable sort by level keeps course order within a level.
    final order = {for (final (i, l) in allLessons.indexed) l.id: i};
    todo.sort((a, b) => a.level != b.level ? a.level.compareTo(b.level) : order[a.id]!.compareTo(order[b.id]!));
    return todo.first;
  }
}
