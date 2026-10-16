import 'package:dartchess/dartchess.dart';

/// What a lesson step asks of the player.
enum StepKind {
  /// Read the explanation; the board may play a few moves to illustrate it.
  show,

  /// Find the right move(s); checked like a puzzle.
  find,
}

/// One screen of a lesson: a short explanation and a board position.
///
/// Moves are written in SAN (`Nf3`, `O-O`, `exd5`) or UCI (`g1f3`), separated by spaces;
/// move numbers such as `1.` or `3...` are ignored.
class LessonStep {
  const LessonStep.show(
    this.text, {
    this.fen,
    this.line = '',
    this.demo = '',
    this.arrows = '',
    this.circles = '',
    this.flip = false,
  })  : kind = StepKind.show,
        solution = '',
        hint = null,
        success = null;

  const LessonStep.find(
    this.text, {
    this.fen,
    this.line = '',
    required this.solution,
    this.hint,
    this.success,
    this.arrows = '',
    this.circles = '',
    this.flip = false,
  })  : kind = StepKind.find,
        demo = '';

  final StepKind kind;
  final String text;

  /// Starting position; null is the initial position.
  final String? fen;

  /// Moves played from [fen] before the step starts (shown at once).
  final String line;

  /// Moves the board plays slowly after the step opens ([StepKind.show] only).
  final String demo;

  /// The player's move, the opponent's reply, the player's next move... ([StepKind.find] only).
  final String solution;

  /// Extra help shown on request.
  final String? hint;

  /// Shown once the move is found.
  final String? success;

  /// Arrows such as `e2e4 g1f3`, shown when the demo ends or the move is found.
  final String arrows;

  /// Highlighted squares such as `d4 e4`.
  final String circles;

  /// Shows the board from the other side than usual.
  final bool flip;

  /// Resolves the moves of this step into positions. Throws [FormatException] for bad content.
  StepBoard resolve() {
    Position pos = fen == null ? Chess.initial : Chess.fromSetup(Setup.parseFen(fen!));
    NormalMove? last;
    for (final m in parseMoves(pos, line)) {
      pos = pos.play(m.$1);
      last = m.$1;
    }
    final demoMoves = [for (final m in parseMoves(pos, demo)) m.$1];
    final sol = parseMoves(pos, solution);
    return StepBoard(
      start: pos,
      lastMove: last,
      demo: demoMoves,
      solution: [for (final m in sol) m.$1.uci],
      solutionSan: [for (final m in sol) m.$2],
      arrows: [
        for (final a in _tokens(arrows))
          (Square.fromName(a.substring(0, 2)), Square.fromName(a.substring(2, 4))),
      ],
      circles: [for (final c in _tokens(circles)) Square.fromName(c)],
    );
  }
}

/// A step's moves, resolved against the board.
class StepBoard {
  const StepBoard({
    required this.start,
    required this.lastMove,
    required this.demo,
    required this.solution,
    required this.solutionSan,
    required this.arrows,
    required this.circles,
  });

  final Position start;
  final NormalMove? lastMove;
  final List<NormalMove> demo;

  /// Solution in UCI, as puzzles store it.
  final List<String> solution;
  final List<String> solutionSan;
  final List<(Square, Square)> arrows;
  final List<Square> circles;

  /// Positions while the demo plays: the start, then after each demo move.
  List<Position> get demoPositions {
    final out = [start];
    for (final m in demo) {
      out.add(out.last.play(m));
    }
    return out;
  }
}

Iterable<String> _tokens(String s) => s.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);

final _uci = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');
final _moveNumber = RegExp(r'^\d+\.+');

/// Parses space-separated SAN or UCI moves played from [from].
/// Returns each move with its SAN. Throws [FormatException] on an illegal move.
List<(NormalMove, String)> parseMoves(Position from, String moves) {
  var pos = from;
  final out = <(NormalMove, String)>[];
  for (var t in _tokens(moves)) {
    t = t.replaceFirst(_moveNumber, '');
    if (t.isEmpty) continue;
    final Move? m = _uci.hasMatch(t) ? Move.parse(t) : pos.parseSan(t.replaceAll(RegExp(r'[!?]+$'), ''));
    if (m is! NormalMove || !pos.isLegal(m)) {
      throw FormatException('Illegal move "$t" in ${pos.fen}');
    }
    final (next, san) = pos.makeSan(m);
    out.add((m, san));
    pos = next;
  }
  return out;
}
