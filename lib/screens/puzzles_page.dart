import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../app/board_style.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../data/puzzles.dart';
import '../widgets/board_layout.dart';
import '../widgets/common.dart';

enum _Status { solving, solved, wrong }

class PuzzlesPage extends StatefulWidget {
  const PuzzlesPage({super.key});

  @override
  State<PuzzlesPage> createState() => _PuzzlesPageState();
}

class _PuzzlesPageState extends State<PuzzlesPage> {
  int _index = 0;
  late Position _pos;
  Move? _lastMove;
  _Status _status = _Status.solving;
  bool _hint = false;
  bool _showSolution = false;
  final _solved = <int>{};
  late final ChessboardController _board;

  Puzzle get _puzzle => starterPuzzles[_index];
  NormalMove get _solution => NormalMove.fromUci(_puzzle.solution);

  @override
  void initState() {
    super.initState();
    _pos = Chess.fromSetup(Setup.parseFen(_puzzle.fen));
    _board = ChessboardController(game: _game());
  }

  @override
  void dispose() {
    _board.dispose();
    super.dispose();
  }

  GameData _game() => GameData(
        fen: _pos.fen,
        lastMove: _lastMove,
        playerSide: _status == _Status.solved
            ? PlayerSide.none
            : (_pos.turn == Side.white ? PlayerSide.white : PlayerSide.black),
        sideToMove: _pos.turn,
        validMoves: makeLegalMoves(_pos),
        kingSquareInCheck: _pos.isCheck ? _pos.board.kingOf(_pos.turn) : null,
      );

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    final correct = move is NormalMove && move.from == _solution.from && move.to == _solution.to;
    if (correct) {
      setState(() {
        _pos = _pos.playUnchecked(move);
        _lastMove = move;
        _status = _Status.solved;
        _showSolution = false;
        _solved.add(_index);
      });
      _board.updatePosition(_game());
    } else {
      setState(() => _status = _Status.wrong);
      _board.updatePosition(_game(), animate: false);
    }
  }

  void _load(int index) {
    setState(() {
      _index = index;
      _pos = Chess.fromSetup(Setup.parseFen(_puzzle.fen));
      _lastMove = null;
      _status = _Status.solving;
      _hint = false;
      _showSolution = false;
    });
    _board.updatePosition(_game(), animate: false, resetPremove: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = SettingsScope.of(context);
    final style = BoardStyle.forTheme(s.theme);
    final side = _pos.turn == Side.white ? 'White' : 'Black';
    final goal = _puzzle.goal == PuzzleGoal.mate ? 'Find the checkmate' : 'Find the winning move';

    final (statusText, statusTone) = switch (_status) {
      _Status.solving => (_hint ? _puzzle.hint : '$goal for $side.', _hint ? BubbleTone.info : BubbleTone.move),
      _Status.solved => (
          _puzzle.goal == PuzzleGoal.mate
              ? 'Correct! That\'s checkmate.'
              : 'Correct! The knight attacks the king and the queen together. Next move you win the queen.',
          BubbleTone.good
        ),
      _Status.wrong => ('Not quite. Look again: checks, captures, threats.', BubbleTone.warning),
    };

    final panel = SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Row(children: [
            Pill(_puzzle.theme),
            const SizedBox(width: 8),
            Pill('Rating ${_puzzle.rating}', color: p.muted),
            const Spacer(),
            Text('${_solved.length}/${starterPuzzles.length} solved', style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
          const SizedBox(height: 16),
          Text('$side to move',
              style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          CoachBubble(text: statusText, tone: statusTone),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Button(
              onPressed: _status == _Status.solved ? null : () => setState(() => _hint = true),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(FluentIcons.lightbulb, size: 14),
                SizedBox(width: 6),
                Text('Hint'),
              ]),
            ),
            Button(
              onPressed: _status == _Status.solved ? null : () => setState(() => _showSolution = true),
              child: const Text('Show solution'),
            ),
            FilledButton(
              onPressed: () => _load((_index + 1) % starterPuzzles.length),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Next puzzle'),
                SizedBox(width: 6),
                Icon(FluentIcons.chevron_right, size: 12),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Text('Today\'s set', style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final (i, pz) in starterPuzzles.indexed)
                HoverButton(
                  onPressed: () => _load(i),
                  builder: (context, states) => Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    decoration: BoxDecoration(
                      color: i == _index || states.isHovered ? p.surfaceAlt : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(
                        _solved.contains(i) ? FluentIcons.completed_solid : FluentIcons.circle_ring,
                        size: 14,
                        color: _solved.contains(i) ? p.success : p.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(pz.theme, style: TextStyle(color: p.text))),
                      Text('${pz.rating}', style: TextStyle(color: p.muted, fontSize: 12)),
                    ]),
                  ),
                ),
          const SizedBox(height: 8),
          Text('Preview set. Milestone 3 adds thousands of puzzles and puzzles from your own games.',
              style: TextStyle(color: p.muted, fontSize: 12)),
        ],
      ),
    );

    return PageFrame(
      title: 'Puzzles',
      subtitle: isMobile(context) ? null : 'Sharpen your tactics, a few minutes at a time',
      scroll: false,
      child: BoardLayout(
        board: (size) => Chessboard(
          size: size,
          controller: _board,
          settings: style.settings(coordinates: s.showCoordinates),
          orientation: Setup.parseFen(_puzzle.fen).turn,
          onMove: _onMove,
          shapes: _showSolution
              ? {Arrow(color: p.success.withValues(alpha: 0.85), orig: _solution.from, dest: _solution.to)}
              : const {},
        ),
        panel: panel,
      ),
    );
  }
}
