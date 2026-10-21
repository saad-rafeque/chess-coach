import 'dart:math' as math;

/// A Glicko-2 rating (Glickman, 2012), as used for Lichess puzzles.
class Rating {
  const Rating(this.rating, this.deviation, this.volatility);

  /// Starting point for a new player: low and uncertain, so it moves fast.
  static const beginner = Rating(900, 350, 0.06);

  final double rating;

  /// Rating deviation: how unsure we are (lower = more certain).
  final double deviation;
  final double volatility;

  Map<String, dynamic> toJson() => {'r': rating, 'rd': deviation, 'v': volatility};

  factory Rating.fromJson(Map<String, dynamic> j) =>
      Rating((j['r'] as num).toDouble(), (j['rd'] as num).toDouble(), (j['v'] as num).toDouble());

  @override
  String toString() => '${rating.round()} ±${deviation.round()}';
}

const _scale = 173.7178;

/// Updates [player] after one result against an opponent (a puzzle) rated
/// [opponent] with deviation [opponentDeviation]. [score] is 1 (solved) or 0.
Rating glicko2Update(Rating player, double opponent, double opponentDeviation, double score,
    {double tau = 0.5, double minDeviation = 45, double maxDeviation = 350}) {
  final mu = (player.rating - 1500) / _scale;
  final phi = player.deviation / _scale;
  final muJ = (opponent - 1500) / _scale;
  final phiJ = opponentDeviation / _scale;

  double g(double p) => 1 / math.sqrt(1 + 3 * p * p / (math.pi * math.pi));
  final gJ = g(phiJ);
  final e = 1 / (1 + math.exp(-gJ * (mu - muJ)));
  final v = 1 / (gJ * gJ * e * (1 - e));
  final delta = v * gJ * (score - e);

  // New volatility (Illinois algorithm).
  final a = math.log(player.volatility * player.volatility);
  double f(double x) {
    final ex = math.exp(x);
    final d = phi * phi + v + ex;
    return ex * (delta * delta - phi * phi - v - ex) / (2 * d * d) - (x - a) / (tau * tau);
  }

  var lo = a;
  double hi;
  if (delta * delta > phi * phi + v) {
    hi = math.log(delta * delta - phi * phi - v);
  } else {
    var k = 1;
    while (f(a - k * tau) < 0) {
      k++;
    }
    hi = a - k * tau;
  }
  var fLo = f(lo), fHi = f(hi);
  for (var i = 0; i < 100 && (hi - lo).abs() > 1e-6; i++) {
    final diff = fHi - fLo;
    if (diff.abs() < 1e-12) break;
    final c = lo + (lo - hi) * fLo / diff;
    final fC = f(c);
    if (fC * fHi <= 0) {
      lo = hi;
      fLo = fHi;
    } else {
      fLo /= 2;
    }
    hi = c;
    fHi = fC;
  }
  final sigma = math.exp(lo / 2);

  final phiStar = math.sqrt(phi * phi + sigma * sigma);
  final phiNew = 1 / math.sqrt(1 / (phiStar * phiStar) + 1 / v);
  final muNew = mu + phiNew * phiNew * gJ * (score - e);
  if (!muNew.isFinite || !phiNew.isFinite || !sigma.isFinite) {
    return player;
  }
  return Rating(
    _scale * muNew + 1500,
    (_scale * phiNew).clamp(minDeviation, maxDeviation),
    sigma,
  );
}
