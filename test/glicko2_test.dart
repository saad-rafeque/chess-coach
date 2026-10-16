import 'package:chess_coach/train/glicko2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches Glickman\'s worked example for a single game', () {
    // Example from the Glicko-2 paper: 1500 ±200, σ 0.06 beats a 1400 ±30 player.
    final r = glicko2Update(const Rating(1500, 200, 0.06), 1400, 30, 1, minDeviation: 0);
    expect(r.rating, closeTo(1563.6, 0.5));
    expect(r.deviation, closeTo(175.4, 0.5));
    expect(r.volatility, closeTo(0.06, 0.0005));
  });

  test('solving raises, failing lowers, certainty grows', () {
    const start = Rating.beginner;
    final up = glicko2Update(start, 900, 80, 1);
    final down = glicko2Update(start, 900, 80, 0);
    expect(up.rating, greaterThan(start.rating));
    expect(down.rating, lessThan(start.rating));
    expect(up.deviation, lessThan(start.deviation));
  });

  test('converges toward the level of puzzles you solve half the time', () {
    var r = Rating.beginner;
    for (var i = 0; i < 200; i++) {
      r = glicko2Update(r, 1300, 80, i.isEven ? 1 : 0);
    }
    expect(r.rating, closeTo(1300, 60));
    expect(r.deviation, lessThan(120));
  });

  test('json round trip', () {
    const r = Rating(1234.5, 88, 0.059);
    final back = Rating.fromJson(r.toJson());
    expect(back.rating, r.rating);
    expect(back.deviation, r.deviation);
  });
}
