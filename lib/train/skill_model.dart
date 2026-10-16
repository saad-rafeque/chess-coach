import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

import '../coach/coach_player.dart';
import '../data/curriculum.dart';
import '../data/event_store.dart';
import '../data/game_record.dart';
import '../lessons/progress.dart';
import '../puzzles/puzzle.dart';
import '../review/game_review.dart';
import 'glicko2.dart';

/// Event type for one flashcard review (see cards.dart).
const cardEventType = 'card';

/// Ratings are "unknown" until the deviation drops below this.
const _ratedDeviation = 300.0;

/// Expected score the coach aims for in games: challenging, but winnable.
const targetScore = 0.45;

/// What the coach knows about the player: a Glicko-2 rating per skill area and per
/// puzzle theme, built from games, puzzle attempts and lesson exercises.
class SkillModel {
  SkillModel._({
    required this.areas,
    required this.themes,
    required this.games,
    required this.gamesPlayed,
    required this.streakDays,
    required this.activeToday,
  });

  factory SkillModel.fromEvents(Iterable<AppEvent> events, {DateTime? now}) {
    final areas = {for (final a in Area.all) a: Rating.beginner};
    final themes = <String, Rating>{};
    var games = Rating.beginner;
    var gamesPlayed = 0;
    final days = <DateTime>{};
    final records = <String, GameRecord>{};

    void update(String area, double opponent, double rd, double score) =>
        areas[area] = glicko2Update(areas[area]!, opponent, rd, score);

    void phases(GameRecord game, Map<int, MoveQuality> grades) {
      final positions = game.positions();
      final errors = <String, int>{}, counts = <String, int>{};
      var blunders = 0;
      for (final MapEntry(key: ply, value: q) in grades.entries) {
        if (ply >= positions.length - 1) continue;
        final area = _phaseOf(positions[ply], ply);
        counts[area] = (counts[area] ?? 0) + 1;
        if (q.index >= MoveQuality.mistake.index) errors[area] = (errors[area] ?? 0) + 1;
        if (q == MoveQuality.blunder) blunders++;
      }
      final elo = game.coachElo.toDouble();
      for (final MapEntry(key: area, value: n) in counts.entries) {
        if (n < 3) continue;
        final e = errors[area] ?? 0;
        update(area, elo, 100, e == 0 ? 1 : (e == 1 ? 0.5 : 0));
      }
      if (grades.length >= 5) update(Area.blunders, elo, 100, blunders == 0 ? 1 : 0);
    }

    final reviewed = <String>{};
    for (final e in events) {
      final t = e.time.toLocal();
      switch (e.type) {
        case puzzleEventType:
          final ok = e.data['solved'] == true ? 1.0 : 0.0;
          final pr = (e.data['puzzleRating'] as num?)?.toDouble();
          if (pr == null) break;
          final tags = ((e.data['themes'] as List?) ?? const []).cast<String>();
          if (e.data['rated'] == false) {
            // A puzzle made from your own mistake: did you fix it this time?
            update(Area.blunders, pr, 100, ok);
          } else {
            update(Area.tactics, pr, 80, ok);
            if (tags.contains('opening')) update(Area.openings, pr, 80, ok);
            if (tags.contains('middlegame')) update(Area.middlegame, pr, 80, ok);
            if (tags.contains('endgame')) update(Area.endgames, pr, 80, ok);
            if (tags.contains('hangingPiece')) update(Area.blunders, pr, 80, ok);
            for (final tag in tags) {
              if (!themeNames.containsKey(tag)) continue;
              themes[tag] = glicko2Update(themes[tag] ?? Rating.beginner, pr, 80, ok);
            }
          }
          days.add(DateTime(t.year, t.month, t.day));
        case lessonEventType:
          final solved = e.data['solved'];
          final area = e.data['area'] as String?;
          final level = (e.data['level'] as num?)?.toDouble();
          if (solved is bool && area != null && level != null && areas.containsKey(area)) {
            update(area, level, 100, solved ? 1 : 0);
          }
          days.add(DateTime(t.year, t.month, t.day));
        case GameRecord.eventType:
          final g = GameRecord.fromEvent(e);
          records[g.id] = g;
          games = glicko2Update(games, g.coachElo.toDouble(), 50, g.playerScore);
          gamesPlayed++;
          days.add(DateTime(t.year, t.month, t.day));
        case GameAnalysis.eventType:
          final g = records[e.data['game']];
          if (g == null || !reviewed.add(g.id)) break;
          final review = buildReview(g, GameAnalysis.fromData(e.data));
          phases(g, {for (final m in review.movesOf(g.playerSide)) m.ply: m.quality});
        case cardEventType:
          days.add(DateTime(t.year, t.month, t.day));
      }
    }
    // Games never reviewed still teach something through their live grades (Training mode).
    for (final g in records.values) {
      if (!reviewed.contains(g.id) && g.grades.isNotEmpty) phases(g, g.grades);
    }

    final today = now ?? DateTime.now();
    var day = DateTime(today.year, today.month, today.day);
    final activeToday = days.contains(day);
    if (!activeToday) day = day.subtract(const Duration(days: 1));
    var streak = 0;
    while (days.contains(day)) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return SkillModel._(
      areas: areas,
      themes: themes,
      games: games,
      gamesPlayed: gamesPlayed,
      streakDays: streak,
      activeToday: activeToday,
    );
  }

  static final _cache = Expando<(int, SkillModel)>();

  /// The model for [store], rebuilt only when events were added.
  static SkillModel of(EventStore store) {
    final n = store.events.length;
    final hit = _cache[store];
    if (hit != null && hit.$1 == n) return hit.$2;
    final model = SkillModel.fromEvents(store.events);
    _cache[store] = (n, model);
    return model;
  }

  /// Rating per skill area (see [Area]).
  final Map<String, Rating> areas;

  /// Rating per puzzle theme (fork, pin, mateIn2...).
  final Map<String, Rating> themes;

  /// Playing strength from results against the coach.
  final Rating games;
  final int gamesPlayed;

  /// Consecutive days with any training, up to today.
  final int streakDays;
  final bool activeToday;

  bool rated(String area) => areas[area]!.deviation < _ratedDeviation;
  bool get hasData => gamesPlayed > 0 || Area.all.any(rated);

  /// 0..1 progress from 400 to the 2000 target.
  double skill(String area) => ((areas[area]!.rating - 400) / 1600).clamp(0, 1);

  /// Overall estimate: games and areas weighted by how certain each rating is.
  int? get estimatedRating {
    var sum = 0.0, weight = 0.0;
    void add(Rating r, double factor) {
      if (r.deviation >= _ratedDeviation) return;
      final w = factor / (r.deviation * r.deviation);
      sum += r.rating * w;
      weight += w;
    }

    add(games, 2);
    for (final a in Area.all) {
      add(areas[a]!, 1);
    }
    return weight == 0 ? null : (sum / weight).round();
  }

  /// The rated area with the lowest rating; unrated areas count as weakest.
  String get weakestArea {
    final sorted = [...Area.all]..sort((a, b) {
        final ra = rated(a) ? areas[a]!.rating : 0, rb = rated(b) ? areas[b]!.rating : 0;
        return ra.compareTo(rb);
      });
    return sorted.first;
  }

  /// The tactical theme with the lowest rating among those tried a few times.
  String? get weakestTheme {
    String? worst;
    for (final MapEntry(key: t, value: r) in themes.entries) {
      if (r.deviation >= _ratedDeviation || t == 'endgame' || t == 'middlegame' || t == 'opening') continue;
      if (worst == null || r.rating < themes[worst]!.rating) worst = t;
    }
    return worst;
  }

  /// Coach strength that gives the player about a [targetScore] expected score.
  int get recommendedCoachElo {
    final base = games.deviation < _ratedDeviation ? games.rating : (estimatedRating ?? 700).toDouble();
    final offset = 400 * math.log(1 / targetScore - 1) / math.ln10;
    return ((base + offset) / 50).round().clamp(8, 50) * 50;
  }
}

/// Name for a rating band, as shown on Home.
String levelName(int rating) => switch (rating) {
      < 800 => 'Beginner',
      < 1200 => 'Improving beginner',
      < 1600 => 'Intermediate',
      < 1800 => 'Club player',
      < 2000 => 'Strong club player',
      _ => 'Expert',
    };

/// Opening for the first ten moves, endgame with six or fewer pieces besides kings and pawns.
String _phaseOf(Position pos, int ply) {
  final b = pos.board;
  final pieces = (b.occupied.size - b.pawns.size - b.kings.size);
  if (pieces <= 6) return Area.endgames;
  if (ply < 20) return Area.openings;
  return Area.middlegame;
}
