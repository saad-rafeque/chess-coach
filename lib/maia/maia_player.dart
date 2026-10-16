import 'dart:isolate';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';

import 'maia_net.dart';

/// Human-like opponent: Maia nets trained on 1100–1900 rated Lichess games.
class MaiaPlayer {
  MaiaPlayer({Future<Uint8List> Function(int rating)? loader}) : _loader = loader ?? _loadAsset;

  static const ratings = [1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900];

  /// One player for the whole app, so loaded nets are reused.
  static final shared = MaiaPlayer();
  static const maxElo = 1900;

  final Future<Uint8List> Function(int rating) _loader;
  final _cache = <int, Uint8List>{};

  static Future<Uint8List> _loadAsset(int rating) async =>
      (await rootBundle.load('assets/maia/maia-$rating.pb.gz')).buffer.asUint8List();

  /// The net closest to [elo].
  static int netFor(int elo) => (((elo.clamp(1100, 1900) + 50) ~/ 100) * 100).clamp(1100, 1900);

  /// Below 1100 the 1100 net is sampled more loosely, which adds the
  /// kind of slips weaker players make.
  static double temperatureFor(int elo) {
    if (elo >= 1100) return 1.0;
    return 1.0 + (1100 - elo.clamp(400, 1100)) / 700 * 0.8;
  }

  /// Move probabilities after [moves] (UCI, from [startFen]) at strength [elo].
  Future<Map<NormalMove, double>> policy(List<String> moves, int elo, {String? startFen}) async {
    final rating = netFor(elo);
    final bytes = _cache[rating] ??= await _loader(rating);
    final start = startFen ?? Chess.initial.fen;
    final result = await Isolate.run(() {
      final positions = <Position>[Chess.fromSetup(Setup.parseFen(start))];
      for (final m in moves) {
        positions.add(positions.last.play(Move.parse(m)!));
      }
      final recent = positions.length > 8 ? positions.sublist(positions.length - 8) : positions;
      return {for (final e in MaiaNet.fromGzip(bytes).policy(recent).entries) e.key.uci: e.value};
    });
    return {for (final e in result.entries) NormalMove.fromUci(e.key): e.value};
  }

  /// Samples a move like a human of strength [elo].
  Future<NormalMove?> pick(List<String> moves, int elo, math.Random rnd) async {
    final probs = await policy(moves, elo);
    if (probs.isEmpty) return null;
    return sampleMove(probs, temperatureFor(elo), rnd);
  }
}

/// Draws a move from [probs] sharpened (t < 1) or flattened (t > 1) by [temperature].
NormalMove sampleMove(Map<NormalMove, double> probs, double temperature, math.Random rnd) {
  final entries = probs.entries.toList();
  final weights = [for (final e in entries) math.pow(e.value, 1 / temperature).toDouble()];
  final total = weights.reduce((a, b) => a + b);
  var r = rnd.nextDouble() * total;
  for (var i = 0; i < entries.length; i++) {
    r -= weights[i];
    if (r <= 0) return entries[i].key;
  }
  return entries.last.key;
}
