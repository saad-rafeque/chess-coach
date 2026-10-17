import 'dart:convert';

import 'package:dartchess/dartchess.dart';

import '../coach/coach_player.dart';
import 'event_store.dart';

/// Checks events before the app uses them, whether they come from the local file or from the
/// sync file in Google Drive. A damaged or tampered copy can then neither crash a screen nor
/// poison the ratings: bad events are skipped and everything else still loads. Types this
/// version doesn't know (written by a newer version) are kept when their envelope is sound, so
/// syncing never drops them.
AppEvent? parseEvent(Object? json) {
  if (json is! Map) return null;
  try {
    final e = AppEvent.fromJson(json.cast<String, dynamic>());
    return isValidEvent(e) ? e : null;
  } catch (_) {
    return null;
  }
}

/// Largest event accepted, as JSON characters (a long game with its review is a few kilobytes).
const maxEventChars = 64 * 1024;

final _id = RegExp(r'^[A-Za-z0-9_.:-]{1,64}$');
final _type = RegExp(r'^[a-z_]{1,32}$');
final _uci = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');
final _qualities = {for (final q in MoveQuality.values) q.name};

bool isValidEvent(AppEvent e) {
  if (!_id.hasMatch(e.id) || !_type.hasMatch(e.type) || e.device.length > 64) return false;
  if (e.time.year < 2000 || e.time.year > 2200) return false;
  final String json;
  try {
    json = jsonEncode(e.data);
  } catch (_) {
    return false;
  }
  if (json.length > maxEventChars) return false;
  final d = e.data;
  try {
    // Literal names: these are the stored type keys (see GameRecord, GameAnalysis, puzzle.dart,
    // progress.dart, skill_model.dart and planner.dart), which never change.
    return switch (e.type) {
      'game' => _game(d),
      'review' => _review(d),
      'puzzle' => _puzzle(d),
      'lesson' => _lesson(d),
      'card' => _card(d),
      'activity' => _activity(d),
      'profile' => _int(d['level'], 400, 2600),
      _ => true,
    };
  } catch (_) {
    return false;
  }
}

/// A short identifier (event, puzzle, lesson or card id).
bool _key(Object? v, {int max = 64}) => v is String && v.isNotEmpty && v.length <= max && !v.contains('\n');
bool _text(Object? v, {int max = 64}) => v == null || (v is String && v.length <= max);
bool _bool(Object? v) => v == null || v is bool;
bool _int(Object? v, int lo, int hi, {bool optional = false}) => v == null ? optional : v is int && v >= lo && v <= hi;
bool _num(Object? v, num lo, num hi, {bool optional = false}) =>
    v == null ? optional : v is num && v.isFinite && v >= lo && v <= hi;

bool _game(Map<String, dynamic> d) {
  final moves = d['moves'];
  if (moves is! List || moves.length > 1000) return false;
  if (!const {null, 'white', 'black'}.contains(d['side'])) return false;
  if (!_int(d['elo'], 0, 4000, optional: true)) return false;
  if (!const {null, '1-0', '0-1', '1/2-1/2', '*'}.contains(d['result'])) return false;
  if (!_text(d['ending'], max: 32)) return false;
  final grades = d['grades'];
  if (grades != null) {
    if (grades is! Map) return false;
    for (final MapEntry(:key, :value) in grades.entries) {
      final ply = key is String ? int.tryParse(key) : null;
      if (ply == null || ply < 0 || ply >= moves.length || !_qualities.contains(value)) return false;
    }
  }
  // Every move must be legal from the start, as the review and the puzzles replay them.
  Position p = Chess.initial;
  for (final m in moves) {
    if (m is! String || !_uci.hasMatch(m)) return false;
    final move = Move.parse(m);
    if (move == null) return false;
    try {
      p = p.play(move);
    } catch (_) {
      return false;
    }
  }
  return true;
}

bool _review(Map<String, dynamic> d) {
  final scores = d['scores'], best = d['best'];
  if (!_key(d['game']) || scores is! List || best is! List) return false;
  if (scores.isEmpty || scores.length > 1001 || scores.length != best.length) return false;
  for (final s in scores) {
    if (s is! Map) return false;
    final mate = s['mate'];
    if (mate != null ? !_int(mate, -1000, 1000) : !_int(s['cp'], -100000, 100000)) return false;
  }
  return best.every((b) => b == null || (b is String && _uci.hasMatch(b)));
}

bool _puzzle(Map<String, dynamic> d) {
  final themes = d['themes'];
  return _key(d['id']) &&
      _bool(d['solved']) &&
      _bool(d['rated']) &&
      _num(d['puzzleRating'], 0, 4000, optional: true) &&
      (themes == null || (themes is List && themes.length <= 64 && themes.every((t) => _key(t))));
}

bool _lesson(Map<String, dynamic> d) =>
    _key(d['lesson']) &&
    _int(d['step'], 0, 999) &&
    _int(d['steps'], 0, 999, optional: true) &&
    _text(d['area'], max: 32) &&
    _num(d['level'], 0, 4000, optional: true) &&
    _bool(d['solved']) &&
    _bool(d['done']);

bool _card(Map<String, dynamic> d) => _key(d['id'], max: 128) && _text(d['kind'], max: 32) && _int(d['grade'], 1, 4);

bool _activity(Map<String, dynamic> d) {
  final x = d['x'];
  return _key(d['kind'], max: 32) &&
      (x == null || (x is List && x.length <= 16 && x.every((v) => _num(v, -1e6, 1e6)))) &&
      _num(d['reward'], -1000, 1000, optional: true) &&
      _num(d['minutes'], 0, 10000, optional: true) &&
      _text(d['area'], max: 32);
}
