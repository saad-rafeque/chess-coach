import 'dart:math' as math;

import '../data/curriculum.dart';
import '../data/event_store.dart';
import '../data/game_record.dart';
import '../lessons/progress.dart';
import '../puzzles/puzzle.dart';
import 'skill_model.dart';

/// Kinds of training the planner can choose from (the bandit's arms).
enum ActivityKind { puzzles, themePuzzles, review, lesson, endgame, game }

const activityEventType = 'activity';

/// One block of a training session.
class Activity {
  const Activity({
    required this.kind,
    required this.minutes,
    required this.title,
    required this.detail,
    required this.area,
    required this.features,
    this.count = 0,
    this.theme,
    this.lesson,
  });

  final ActivityKind kind;
  final int minutes;
  final String title;
  final String detail;

  /// Skill area this block trains.
  final String area;

  /// Context the bandit saw when choosing it (stored with the reward).
  final List<double> features;

  /// Puzzles to solve or cards to review.
  final int count;

  /// Puzzle theme for themed blocks.
  final String? theme;
  final Lesson? lesson;
}

/// Event data stored when a block is finished; [reward] is 0..1.
Map<String, dynamic> activityData(Activity a, double reward) =>
    {'kind': a.kind.name, 'x': a.features, 'reward': reward, 'minutes': a.minutes, 'area': a.area};

/// Chooses what to train with a contextual bandit (LinUCB, one linear model per kind).
///
/// Context per kind: [bias, skill gap of its area, pending work, time fit, days since last done].
/// The reward is the improvement measured after the block (rating gain or recall rate), so
/// the planner learns which kinds of training pay off for this player. Priors encode the
/// coaching rules of thumb until there is data.
class Planner {
  Planner({required this.skills, required this.lessons, required this.dueCards, required Iterable<AppEvent> events,
      DateTime? now})
      : _now = now ?? DateTime.now() {
    for (final k in ActivityKind.values) {
      _a[k] = _identity(_lambda);
      _b[k] = [for (final w in _prior[k]!) w * _lambda];
    }
    for (final e in events) {
      if (e.type == activityEventType) {
        final k = ActivityKind.values.asNameMap()[e.data['kind']];
        final x = ((e.data['x'] as List?) ?? const []).map((v) => (v as num).toDouble()).toList();
        final r = (e.data['reward'] as num?)?.toDouble();
        if (k == null || x.length != _d || r == null) continue;
        for (var i = 0; i < _d; i++) {
          for (var j = 0; j < _d; j++) {
            _a[k]![i][j] += x[i] * x[j];
          }
          _b[k]![i] += r * x[i];
        }
      }
      final kind = switch (e.type) {
        puzzleEventType => ActivityKind.puzzles,
        lessonEventType => ActivityKind.lesson,
        cardEventType => ActivityKind.review,
        GameRecord.eventType => ActivityKind.game,
        activityEventType => ActivityKind.values.asNameMap()[e.data['kind']],
        _ => null,
      };
      if (kind != null) _last[kind] = e.time;
    }
  }

  factory Planner.forStore(EventStore store, {required int dueCards}) => Planner(
        skills: SkillModel.of(store),
        lessons: LessonProgress.fromEvents(store.events),
        dueCards: dueCards,
        events: store.events,
      );

  final SkillModel skills;
  final LessonProgress lessons;
  final int dueCards;
  final DateTime _now;

  static const _d = 5;
  static const _lambda = 2.0;
  static const _alpha = 0.1;

  static const _prior = {
    ActivityKind.puzzles: [0.25, 0.30, 0.0, 0.10, 0.20],
    ActivityKind.themePuzzles: [0.20, 0.35, 0.0, 0.10, 0.20],
    ActivityKind.review: [0.10, 0.10, 0.80, 0.10, 0.20],
    ActivityKind.lesson: [0.20, 0.30, 0.30, 0.20, 0.20],
    ActivityKind.endgame: [0.10, 0.40, 0.0, 0.10, 0.20],
    ActivityKind.game: [0.15, 0.30, 0.0, 0.40, 0.30],
  };

  final _a = <ActivityKind, List<List<double>>>{};
  final _b = <ActivityKind, List<double>>{};
  final _last = <ActivityKind, DateTime>{};

  /// Ideal length of each kind of block, in minutes.
  static const _ideal = {
    ActivityKind.puzzles: 5,
    ActivityKind.themePuzzles: 6,
    ActivityKind.review: 6,
    ActivityKind.lesson: 10,
    ActivityKind.endgame: 6,
    ActivityKind.game: 30,
  };

  double _gap(String area) => skills.rated(area) ? 1 - skills.skill(area) : 0.8;

  String _areaOf(ActivityKind k) => switch (k) {
        ActivityKind.puzzles || ActivityKind.themePuzzles => Area.tactics,
        ActivityKind.review => Area.openings,
        ActivityKind.lesson => lessons.next()?.area ?? Area.tactics,
        ActivityKind.endgame => Area.endgames,
        ActivityKind.game => Area.blunders,
      };

  List<double> features(ActivityKind k, int minutes) {
    final next = lessons.next();
    final pending = switch (k) {
      ActivityKind.review => math.min(dueCards / 10, 1.0),
      ActivityKind.lesson => next == null ? 0.0 : lessons.fraction(next),
      _ => 0.0,
    };
    final last = _last[k];
    final stale = last == null ? 1.0 : math.min(_now.difference(last).inHours / (24 * 7), 1.0);
    return [1, _gap(_areaOf(k)), pending, math.min(minutes / _ideal[k]!, 1.0), stale];
  }

  /// Upper confidence bound of the expected improvement for [k] in context [x].
  double score(ActivityKind k, List<double> x) {
    final inv = _inverse(_a[k]!);
    final theta = _mulVec(inv, _b[k]!);
    final mean = _dot(theta, x);
    final spread = math.sqrt(math.max(0, _dot(x, _mulVec(inv, x))));
    return mean + _alpha * spread;
  }

  bool _available(ActivityKind k) => switch (k) {
        ActivityKind.review => dueCards > 0,
        ActivityKind.themePuzzles => skills.weakestTheme != null,
        ActivityKind.lesson => lessons.next() != null,
        _ => true,
      };

  int _minMinutes(ActivityKind k) => switch (k) {
        ActivityKind.game => 25,
        ActivityKind.lesson => 5,
        ActivityKind.review || ActivityKind.puzzles => 1,
        _ => 4,
      };

  /// Builds a session that fills about [minutes].
  List<Activity> plan(int minutes) {
    final out = <Activity>[];
    var left = minutes;
    final used = <ActivityKind>{};
    if (minutes >= 10) {
      out.add(_make(ActivityKind.puzzles, 3, minutes, warmUp: true));
      left -= 3;
      // Short sessions get variety; long ones may add targeted puzzles later.
      if (minutes < 30) used.add(ActivityKind.puzzles);
    }
    var games = 0;
    while (left > 0) {
      ActivityKind? best;
      var bestScore = double.negativeInfinity;
      for (final k in ActivityKind.values) {
        if (!_available(k) || _minMinutes(k) > left) continue;
        if (k == ActivityKind.game ? games >= (minutes >= 90 ? 2 : 1) : used.contains(k)) continue;
        final s = score(k, features(k, left));
        if (s > bestScore) {
          bestScore = s;
          best = k;
        }
      }
      if (best == null) break;
      final a = _make(best, left, minutes);
      out.add(a);
      left -= a.minutes;
      used.add(best);
      if (best == ActivityKind.game) games++;
    }
    return out;
  }

  Activity _make(ActivityKind k, int left, int total, {bool warmUp = false}) {
    // Short sessions get short blocks, so there is room for variety.
    final cap = total < 30 ? 4 : 10;
    final x = features(k, left);
    switch (k) {
      case ActivityKind.puzzles:
        final n = warmUp ? 3 : math.max(3, math.min(left, 10));
        return Activity(
            kind: k,
            minutes: warmUp ? 3 : math.min(left, 10),
            title: warmUp ? 'Warm-up: 3 puzzles' : '$n rated puzzles',
            detail: 'Puzzles near your level',
            area: Area.tactics,
            features: x,
            count: n);
      case ActivityKind.themePuzzles:
        final t = skills.weakestTheme!;
        final m = math.min(left, 8);
        return Activity(
            kind: k,
            minutes: m,
            title: '${math.max(3, m)} ${themeNames[t]!.toLowerCase()} puzzles',
            detail: 'Your weakest tactic right now',
            area: Area.tactics,
            features: x,
            count: math.max(3, m),
            theme: t);
      case ActivityKind.review:
        final n = math.min(dueCards, math.min(left, cap));
        return Activity(
            kind: k,
            minutes: n,
            title: 'Review $n card${n == 1 ? '' : 's'}',
            detail: 'Repertoire moves and your old mistakes',
            area: Area.openings,
            features: x,
            count: n);
      case ActivityKind.lesson:
        final l = lessons.next()!;
        final stepsLeft = (l.steps.length * (1 - lessons.fraction(l))).ceil();
        return Activity(
            kind: k,
            minutes: math.min(left, math.max(5, math.min(total < 30 ? 8 : 15, stepsLeft * 2))),
            title: 'Lesson: ${l.title}',
            detail: '$stepsLeft step${stepsLeft == 1 ? '' : 's'} to go',
            area: l.area,
            features: x,
            lesson: l);
      case ActivityKind.endgame:
        final m = math.min(left, 8);
        return Activity(
            kind: k,
            minutes: m,
            title: '${math.max(3, m ~/ 2)} endgame puzzles',
            detail: 'Turn advantages into wins',
            area: Area.endgames,
            features: x,
            count: math.max(3, m ~/ 2),
            theme: 'endgame');
      case ActivityKind.game:
        return Activity(
            kind: k,
            minutes: 30,
            title: 'Training game',
            detail: 'Vs coach ~${skills.recommendedCoachElo}, then review it',
            area: Area.blunders,
            features: x);
    }
  }

  /// Short summary for the Home tiles.
  String preview(int minutes) {
    final p = plan(minutes);
    if (p.isEmpty) return 'Quick puzzles';
    return p.map((a) => a.title.replaceFirst('Warm-up: ', '')).join(', ');
  }
}

List<List<double>> _identity(double v) =>
    List.generate(Planner._d, (i) => List.generate(Planner._d, (j) => i == j ? v : 0.0));

double _dot(List<double> a, List<double> b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

List<double> _mulVec(List<List<double>> m, List<double> v) => [for (final row in m) _dot(row, v)];

/// Gauss-Jordan inverse of a small positive-definite matrix.
List<List<double>> _inverse(List<List<double>> m) {
  final n = m.length;
  final a = [for (final row in m) [...row]];
  final inv = _identity(1);
  for (var c = 0; c < n; c++) {
    var pivot = c;
    for (var r = c + 1; r < n; r++) {
      if (a[r][c].abs() > a[pivot][c].abs()) pivot = r;
    }
    final rowA = a[c], rowInv = inv[c];
    a[c] = a[pivot];
    a[pivot] = rowA;
    inv[c] = inv[pivot];
    inv[pivot] = rowInv;
    final p = a[c][c];
    for (var j = 0; j < n; j++) {
      a[c][j] /= p;
      inv[c][j] /= p;
    }
    for (var r = 0; r < n; r++) {
      if (r == c) continue;
      final f = a[r][c];
      if (f == 0) continue;
      for (var j = 0; j < n; j++) {
        a[r][j] -= f * a[c][j];
        inv[r][j] -= f * inv[c][j];
      }
    }
  }
  return inv;
}
