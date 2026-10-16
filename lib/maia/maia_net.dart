// Maia (Lc0 SE-ResNet with a convolutional policy head) in pure Dart.
// Reads Lc0 `.pb.gz` weights and returns move probabilities for a position.
// Checked against a numpy reference: see test/maia_test.dart.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartchess/dartchess.dart';

// ---------------------------------------------------------------- protobuf --

class _Pb {
  _Pb(this.b);

  final Uint8List b;
  int i = 0;

  bool get done => i >= b.length;

  int varint() {
    var r = 0, s = 0;
    while (true) {
      final c = b[i++];
      r |= (c & 0x7f) << s;
      if (c & 0x80 == 0) return r;
      s += 7;
    }
  }

  /// Field number -> list of values (Uint8List for length-delimited/fixed32, int for varint).
  Map<int, List<Object>> fields() {
    final out = <int, List<Object>>{};
    while (!done) {
      final key = varint();
      final f = key >> 3;
      final Object v;
      switch (key & 7) {
        case 0:
          v = varint();
        case 2:
          final n = varint();
          v = Uint8List.sublistView(b, i, i + n);
          i += n;
        case 5:
          v = Uint8List.sublistView(b, i, i + 4);
          i += 4;
        case 1:
          v = Uint8List.sublistView(b, i, i + 8);
          i += 8;
        default:
          throw const FormatException('Unsupported protobuf wire type');
      }
      (out[f] ??= []).add(v);
    }
    return out;
  }
}

Map<int, List<Object>> _msg(Object bytes) => _Pb(bytes as Uint8List).fields();

double _f32(Object bytes) => ByteData.sublistView(bytes as Uint8List).getFloat32(0, Endian.little);

/// Dequantises an Lc0 `Layer` (linear 16-bit encoding).
Float32List _layer(Object bytes) {
  final m = _msg(bytes);
  final min = m[1] == null ? 0.0 : _f32(m[1]!.first);
  final max = m[2] == null ? 0.0 : _f32(m[2]!.first);
  final raw = (m[3]?.first as Uint8List?) ?? Uint8List(0);
  final data = ByteData.sublistView(raw);
  final out = Float32List(raw.length ~/ 2);
  final range = (max - min) / 65535.0;
  for (var k = 0; k < out.length; k++) {
    out[k] = min + range * data.getUint16(k * 2, Endian.little);
  }
  return out;
}

/// 3x3 convolution with batch norm (or bias) folded into a per-channel scale and shift.
class _Conv {
  _Conv(Object bytes) {
    final m = _msg(bytes);
    weights = _layer(m[1]!.first);
    final bias = m[2] == null ? null : _layer(m[2]!.first);
    final cout = bias?.length ?? _layer(m[3]!.first).length;
    scale = Float32List(cout)..fillRange(0, cout, 1);
    shift = Float32List(cout);
    if (bias != null) shift.setAll(0, bias);
    if (m[3] != null) {
      final mean = _layer(m[3]!.first), variance = _layer(m[4]!.first);
      final gamma = m[5] == null ? null : _layer(m[5]!.first);
      final beta = m[6] == null ? null : _layer(m[6]!.first);
      for (var c = 0; c < cout; c++) {
        final s = (gamma?[c] ?? 1) / math.sqrt(variance[c] + 1e-5);
        scale[c] = s;
        shift[c] = (beta?[c] ?? 0) - mean[c] * s;
      }
    }
    outputs = cout;
    inputs = weights.length ~/ (cout * 9);
  }

  late final Float32List weights;
  late final Float32List scale;
  late final Float32List shift;
  late final int inputs;
  late final int outputs;

  /// [x] holds [inputs] planes of 64 squares (index = rank * 8 + file).
  Float32List apply(Float32List x, {bool relu = true}) {
    // Pad each plane to 10x10 so the kernel never leaves the buffer.
    final padded = Float32List(inputs * 100);
    for (var c = 0; c < inputs; c++) {
      for (var r = 0; r < 8; r++) {
        for (var f = 0; f < 8; f++) {
          padded[c * 100 + (r + 1) * 10 + f + 1] = x[c * 64 + r * 8 + f];
        }
      }
    }
    final out = Float32List(outputs * 64);
    final acc = Float32List(64);
    for (var o = 0; o < outputs; o++) {
      acc.fillRange(0, 64, 0);
      for (var c = 0; c < inputs; c++) {
        final wBase = (o * inputs + c) * 9;
        final pBase = c * 100;
        for (var ky = 0; ky < 3; ky++) {
          for (var kx = 0; kx < 3; kx++) {
            final w = weights[wBase + ky * 3 + kx];
            if (w == 0) continue;
            var src = pBase + ky * 10 + kx;
            var dst = 0;
            for (var r = 0; r < 8; r++) {
              for (var f = 0; f < 8; f++) {
                acc[dst++] += w * padded[src + f];
              }
              src += 10;
            }
          }
        }
      }
      final s = scale[o], t = shift[o];
      for (var k = 0; k < 64; k++) {
        final v = acc[k] * s + t;
        out[o * 64 + k] = relu && v < 0 ? 0 : v;
      }
    }
    return out;
  }
}

class _Residual {
  _Residual(Object bytes) {
    final m = _msg(bytes);
    conv1 = _Conv(m[1]!.first);
    conv2 = _Conv(m[2]!.first);
    final se = _msg(m[3]!.first);
    w1 = _layer(se[1]!.first);
    b1 = _layer(se[2]!.first);
    w2 = _layer(se[3]!.first);
    b2 = _layer(se[4]!.first);
  }

  late final _Conv conv1, conv2;
  late final Float32List w1, b1, w2, b2;

  Float32List apply(Float32List x) {
    final z = conv2.apply(conv1.apply(x), relu: false);
    final c = conv2.outputs;
    final pooled = Float32List(c);
    for (var ch = 0; ch < c; ch++) {
      var sum = 0.0;
      for (var k = 0; k < 64; k++) {
        sum += z[ch * 64 + k];
      }
      pooled[ch] = sum / 64;
    }
    final hidden = b1.length;
    final h = Float32List(hidden);
    for (var j = 0; j < hidden; j++) {
      var v = b1[j];
      for (var ch = 0; ch < c; ch++) {
        v += w1[j * c + ch] * pooled[ch];
      }
      h[j] = v < 0 ? 0 : v;
    }
    final out = Float32List(c * 64);
    for (var ch = 0; ch < c; ch++) {
      var g = b2[ch], beta = b2[c + ch];
      for (var j = 0; j < hidden; j++) {
        g += w2[ch * hidden + j] * h[j];
        beta += w2[(c + ch) * hidden + j] * h[j];
      }
      final gate = 1 / (1 + math.exp(-g));
      for (var k = 0; k < 64; k++) {
        final v = z[ch * 64 + k] * gate + beta + x[ch * 64 + k];
        out[ch * 64 + k] = v < 0 ? 0 : v;
      }
    }
    return out;
  }
}

// ------------------------------------------------------------------ network --

class MaiaNet {
  MaiaNet._(this._input, this._tower, this._policy1, this._policy);

  /// Parses gzipped Lc0 weights (the `.pb.gz` files Maia ships).
  factory MaiaNet.fromGzip(List<int> bytes) {
    final net = _Pb(Uint8List.fromList(GZipCodec().decode(bytes))).fields();
    final w = _msg(net[10]!.first);
    final format = _msg(_msg(net[4]!.first)[2]!.first);
    if ((format[4]?.first as int?) != 2) {
      throw const FormatException('Only convolutional-policy Lc0 nets are supported');
    }
    return MaiaNet._(
      _Conv(w[1]!.first),
      [for (final r in w[2]!) _Residual(r)],
      _Conv(w[11]!.first),
      _Conv(w[3]!.first),
    );
  }

  final _Conv _input;
  final List<_Residual> _tower;
  final _Conv _policy1;
  final _Conv _policy;

  /// Raw policy output: 80 move planes x 64 from-squares.
  Float32List forward(Float32List planes) {
    var x = _input.apply(planes);
    for (final r in _tower) {
      x = r.apply(x);
    }
    return _policy.apply(_policy1.apply(x), relu: false);
  }

  /// Probability of each legal move in the last position of [history]
  /// (oldest first). Castling is returned as king-to-rook, like dartchess.
  Map<NormalMove, double> policy(List<Position> history) {
    final pos = history.last;
    final out = forward(encodePosition(history));
    final black = pos.turn == Side.black;
    final moves = <NormalMove>[];
    final logits = <double>[];
    for (final e in pos.legalMoves.entries) {
      for (final to in e.value.squares) {
        final piece = pos.board.pieceAt(e.key)!;
        final promotes = piece.role == Role.pawn && (to.rank == Rank.first || to.rank == Rank.eighth);
        for (final promo in promotes ? const [Role.queen, Role.rook, Role.bishop, Role.knight] : const <Role?>[null]) {
          final m = NormalMove(from: e.key, to: to, promotion: promo);
          moves.add(m);
          logits.add(out[movePlane(m, black: black) * 64 + (black ? e.key ^ 56 : e.key)]);
        }
      }
    }
    if (moves.isEmpty) return const {};
    final top = logits.reduce(math.max);
    final exps = [for (final l in logits) math.exp(l - top)];
    final sum = exps.reduce((a, b) => a + b);
    return {for (var k = 0; k < moves.length; k++) moves[k]: exps[k] / sum};
  }
}

// ----------------------------------------------------------------- encoding --

const _knight = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)];
const _dirs = [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)];

/// Output plane (0..79) for [m], seen from the side to move.
int movePlane(NormalMove m, {required bool black}) {
  final f = black ? m.from ^ 56 : m.from;
  final t = black ? m.to ^ 56 : m.to;
  final dx = t % 8 - f % 8, dy = t ~/ 8 - f ~/ 8;
  final promo = m.promotion;
  if (promo != null && promo != Role.knight) {
    final p = switch (promo) {
      Role.rook => 0,
      Role.bishop => 1,
      _ => 2,
    };
    return 64 + (dx + 1) * 3 + p;
  }
  final k = _knight.indexOf((dx, dy));
  if (k >= 0) return 56 + k;
  final steps = math.max(dx.abs(), dy.abs());
  return _dirs.indexOf((dx.sign, dy.sign)) * 7 + steps - 1;
}

String _key(Position p) => p.fen.split(' ').take(4).join(' ');

/// Lc0 classical 112-plane input for the last position of [history] (oldest first).
Float32List encodePosition(List<Position> history) {
  final planes = Float32List(112 * 64);
  final pos = history.last;
  final us = pos.turn;
  final flip = us == Side.black;
  void fill(int plane, double v) => planes.fillRange(plane * 64, plane * 64 + 64, v);

  for (var i = 0; i < 8 && i < history.length; i++) {
    final idx = history.length - 1 - i;
    final p = history[idx];
    final b = p.board;
    const roles = [Role.pawn, Role.knight, Role.bishop, Role.rook, Role.queen, Role.king];
    for (var r = 0; r < 6; r++) {
      final ofRole = b.piecesOf(us, roles[r]);
      final theirs = b.piecesOf(us.opposite, roles[r]);
      for (final sq in ofRole.squares) {
        planes[(i * 13 + r) * 64 + (flip ? sq ^ 56 : sq)] = 1;
      }
      for (final sq in theirs.squares) {
        planes[(i * 13 + 6 + r) * 64 + (flip ? sq ^ 56 : sq)] = 1;
      }
    }
    final key = _key(p);
    if (history.take(idx).any((h) => _key(h) == key)) fill(i * 13 + 12, 1);
  }
  final castles = pos.castles;
  if (castles.rookOf(us, CastlingSide.queen) != null) fill(104, 1);
  if (castles.rookOf(us, CastlingSide.king) != null) fill(105, 1);
  if (castles.rookOf(us.opposite, CastlingSide.queen) != null) fill(106, 1);
  if (castles.rookOf(us.opposite, CastlingSide.king) != null) fill(107, 1);
  if (flip) fill(108, 1);
  fill(109, pos.halfmoves.toDouble());
  fill(111, 1);
  return planes;
}
