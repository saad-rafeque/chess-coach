import 'dart:math' as math;

/// How well a card was remembered.
enum Grade {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const Grade(this.value);
  final int value;
}

/// Memory state of one card under FSRS (Free Spaced Repetition Scheduler, v4.5).
class CardState {
  const CardState({
    required this.stability,
    required this.difficulty,
    required this.due,
    required this.lastReview,
    required this.reps,
    required this.lapses,
  });

  /// Days until recall probability drops to 90%.
  final double stability;

  /// 1 (easy) .. 10 (hard).
  final double difficulty;
  final DateTime due;
  final DateTime lastReview;
  final int reps;
  final int lapses;

  bool isDue(DateTime now) => !due.isAfter(now);
}

/// FSRS v4.5 with the published default parameters and 90% target retention.
class Fsrs {
  const Fsrs({this.retention = 0.9, this.maxInterval = 365});

  static const w = [
    0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474, //
    0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755,
  ];
  static const _decay = -0.5;
  static const _factor = 19 / 81;

  final double retention;
  final int maxInterval;

  /// Probability of recall after [days] with [stability].
  static double retrievability(double days, double stability) =>
      math.pow(1 + _factor * days / stability, _decay).toDouble();

  double _initDifficulty(Grade g) => (w[4] - (g.value - 3) * w[5]).clamp(1, 10);

  int _interval(double stability) {
    final days = stability / _factor * (math.pow(retention, 1 / _decay) - 1);
    return days.round().clamp(1, maxInterval);
  }

  /// The state after reviewing a card (null = new card) with [grade] at [now].
  CardState review(CardState? card, Grade grade, DateTime now) {
    double s, d;
    var lapses = card?.lapses ?? 0;
    if (card == null) {
      s = w[grade.value - 1];
      d = _initDifficulty(grade);
    } else {
      final days = math.max(0, now.difference(card.lastReview).inMinutes / (24 * 60));
      final r = retrievability(days.toDouble(), card.stability);
      // Stability uses the difficulty before this review.
      final oldD = card.difficulty;
      d = oldD - w[6] * (grade.value - 3);
      d = (w[7] * w[4] + (1 - w[7]) * d).clamp(1, 10);
      if (grade == Grade.again) {
        lapses++;
        s = w[11] *
            math.pow(oldD, -w[12]) *
            (math.pow(card.stability + 1, w[13]) - 1) *
            math.exp(w[14] * (1 - r));
        s = math.min(s, card.stability);
      } else {
        final hard = grade == Grade.hard ? w[15] : 1.0;
        final easy = grade == Grade.easy ? w[16] : 1.0;
        s = card.stability *
            (1 +
                math.exp(w[8]) *
                    (11 - oldD) *
                    math.pow(card.stability, -w[9]) *
                    (math.exp(w[10] * (1 - r)) - 1) *
                    hard *
                    easy);
      }
    }
    s = math.max(s, 0.01);
    final due = grade == Grade.again ? now.add(const Duration(minutes: 10)) : now.add(Duration(days: _interval(s)));
    return CardState(
      stability: s,
      difficulty: d,
      due: due,
      lastReview: now,
      reps: (card?.reps ?? 0) + 1,
      lapses: lapses,
    );
  }
}
