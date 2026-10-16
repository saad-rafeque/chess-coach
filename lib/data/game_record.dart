import 'package:dartchess/dartchess.dart';

import '../coach/coach_player.dart';
import 'event_store.dart';

/// A finished game against the coach.
class GameRecord {
  const GameRecord({
    required this.id,
    required this.date,
    required this.playerSide,
    required this.coachElo,
    required this.moves,
    required this.result,
    required this.ending,
    this.grades = const {},
  });

  factory GameRecord.fromEvent(AppEvent e) {
    final d = e.data;
    return GameRecord(
      id: e.id,
      date: e.time.toLocal(),
      playerSide: d['side'] == 'black' ? Side.black : Side.white,
      coachElo: d['elo'] as int? ?? 800,
      moves: (d['moves'] as List<dynamic>).cast<String>(),
      result: d['result'] as String? ?? '*',
      ending: d['ending'] as String? ?? '',
      grades: {
        for (final g in ((d['grades'] as Map?) ?? const {}).entries)
          int.parse(g.key as String): MoveQuality.values.byName(g.value as String),
      },
    );
  }

  final String id;
  final DateTime date;
  final Side playerSide;
  final int coachElo;

  /// Moves in UCI notation.
  final List<String> moves;

  /// PGN result: 1-0, 0-1, 1/2-1/2.
  final String result;

  /// checkmate, resignation, stalemate, draw.
  final String ending;

  /// Live grades of the player's moves (Training mode), by ply.
  final Map<int, MoveQuality> grades;

  static const eventType = 'game';

  Map<String, dynamic> toData() => {
        'side': playerSide.name,
        'elo': coachElo,
        'moves': moves,
        'result': result,
        'ending': ending,
        'grades': {for (final g in grades.entries) '${g.key}': g.value.name},
      };

  /// 1 = player won, 0 = lost, 0.5 = draw.
  double get playerScore {
    if (result == '1/2-1/2') return 0.5;
    final whiteWon = result == '1-0';
    return whiteWon == (playerSide == Side.white) ? 1 : 0;
  }

  String get outcomeLabel => switch (playerScore) {
        1 => 'Won',
        0 => 'Lost',
        _ => 'Draw',
      };

  /// Positions from the start to the final position.
  List<Position> positions() {
    final list = <Position>[Chess.initial];
    for (final uci in moves) {
      list.add(list.last.play(Move.parse(uci)!));
    }
    return list;
  }

  List<String> sans() {
    Position pos = Chess.initial;
    return [
      for (final uci in moves)
        () {
          final (next, san) = pos.makeSan(Move.parse(uci)!);
          pos = next;
          return san;
        }(),
    ];
  }

  String toPgn() {
    final tags = {
      'Event': 'Chess Coach game',
      'Date': '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
      'White': playerSide == Side.white ? 'You' : 'Coach ($coachElo)',
      'Black': playerSide == Side.black ? 'You' : 'Coach ($coachElo)',
      'Result': result,
    };
    final b = StringBuffer();
    tags.forEach((k, v) => b.writeln('[$k "$v"]'));
    b.writeln();
    final s = sans();
    for (var i = 0; i < s.length; i++) {
      if (i.isEven) b.write('${i ~/ 2 + 1}. ');
      b.write('${s[i]} ');
    }
    b.write(result);
    return b.toString();
  }
}
