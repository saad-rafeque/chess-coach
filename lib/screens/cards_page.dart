import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../app/board_style.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../data/event_store.dart';
import '../puzzles/puzzle.dart';
import '../train/cards.dart';
import '../train/fsrs.dart';
import '../train/skill_model.dart';
import '../widgets/board_layout.dart';
import '../widgets/common.dart';

/// Opens the flashcard review with the cards due now. Returns how many were reviewed.
Future<int?> openCardReview(BuildContext context, {int? limit}) =>
    Navigator.of(context).push<int>(FluentPageRoute(builder: (_) => CardsPage(limit: limit)));

/// Spaced-repetition review: each due card is a position to solve. The grade
/// (again / hard / good / easy) comes from how it went, so there is nothing to rate by hand.
class CardsPage extends StatefulWidget {
  const CardsPage({super.key, this.limit, this.moveDelay = const Duration(milliseconds: 550)});

  /// Stop after this many cards (null = all due).
  final int? limit;
  final Duration moveDelay;

  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  late final ChessboardController _board;
  List<StudyCard> _queue = const [];
  int _index = 0;
  PuzzleSession? _session;
  bool _hinted = false;
  bool _wrong = false;
  DateTime _shownAt = DateTime.now();
  Grade? _grade;
  final _grades = <Grade>[];
  String _shownFen = '';

  @override
  void initState() {
    super.initState();
    _board = ChessboardController(
        game: GameData(fen: Chess.initial.fen, playerSide: PlayerSide.none, sideToMove: Side.white, validMoves: const {}));
    final due = CardDeck.fromStore(StoreScope.read(context)).due();
    _queue = widget.limit == null ? due : due.take(widget.limit!).toList();
    _start();
  }

  @override
  void dispose() {
    _session?.dispose();
    _board.dispose();
    super.dispose();
  }

  StudyCard? get _card => _index < _queue.length ? _queue[_index] : null;

  void _start() {
    _session?.removeListener(_onSession);
    _session?.dispose();
    _session = null;
    _hinted = false;
    _wrong = false;
    _grade = null;
    final card = _card;
    if (card == null) return;
    final s = PuzzleSession(card.puzzle, moveDelay: widget.moveDelay, onResult: (_, solved) {
      if (!solved) _wrong = true;
    });
    _session = s..addListener(_onSession);
    _shownFen = s.position.fen;
    _shownAt = DateTime.now();
    _board.updatePosition(_gameData(s), animate: false, resetPremove: true);
    unawaited(s.start());
  }

  GameData _gameData(PuzzleSession s) {
    final pos = s.position;
    final canMove = s.state == PuzzleState.playerToMove || s.state == PuzzleState.wrongMove;
    return GameData(
      fen: pos.fen,
      lastMove: s.lastMove,
      playerSide: canMove ? (s.playerSide == Side.white ? PlayerSide.white : PlayerSide.black) : PlayerSide.none,
      sideToMove: pos.turn,
      validMoves: canMove ? makeLegalMoves(pos) : const {},
      kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
    );
  }

  void _onSession() {
    final s = _session!;
    if (s.finished && _grade == null) _finish(s);
    final fen = s.position.fen;
    _board.updatePosition(_gameData(s), animate: fen != _shownFen);
    _shownFen = fen;
    if (mounted) setState(() {});
  }

  void _finish(PuzzleSession s) {
    final fast = DateTime.now().difference(_shownAt) < const Duration(seconds: 8);
    final grade = s.state == PuzzleState.showingSolution || _wrong
        ? Grade.again
        : _hinted
            ? Grade.hard
            : fast
                ? Grade.easy
                : Grade.good;
    _grade = grade;
    _grades.add(grade);
    StoreScope.read(context).add(cardEventType, cardReviewData(_card!, grade));
  }

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    final s = _session;
    if (s == null || move is! NormalMove) return;
    unawaited(s.playerMove(move).then((ok) {
      if (!ok && mounted) _board.updatePosition(_gameData(s), animate: false);
    }));
  }

  void _next() {
    setState(() => _index++);
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = SettingsScope.of(context);
    final style = BoardStyle.of(settings);
    final s = _session;
    final card = _card;
    final done = card == null;
    void next() {
      if (s != null && s.finished) _next();
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): next,
        const SingleActivator(LogicalKeyboardKey.enter): next,
      },
      child: Focus(autofocus: true, child: _page(p, style, settings, s, card, done)),
    );
  }

  Widget _page(Palette p, BoardStyle style, AppSettings settings, PuzzleSession? s, StudyCard? card, bool done) {
    return PageFrame(
      title: 'Review',
      subtitle: done
          ? 'All done for now'
          : 'Card ${_index + 1} of ${_queue.length} · spaced repetition brings each position back just in time',
      leading: PageBackButton(onPressed: () => Navigator.of(context).pop(_grades.length)),
      scroll: false,
      child: BoardLayout(
        boardLabel: s == null ? 'Review board' : 'Review card. ${s.playerSide == Side.white ? 'White' : 'Black'} to move.',
        board: (size) => Chessboard(
          size: size,
          controller: _board,
          settings: style.settings(coordinates: settings.showCoordinates),
          orientation: s?.playerSide ?? Side.white,
          onMove: _onMove,
          shapes: {
            if (s?.hintSquare != null) Circle(color: p.accent.withValues(alpha: 0.9), orig: s!.hintSquare!),
          },
        ),
        panel: SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: ListView(children: done ? _summary(p) : _status(p, s!, card!)),
        ),
        actions: done
            ? null
            : Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                Button(
                  onPressed: s == null || s.finished
                      ? null
                      : () {
                          _hinted = true;
                          s.hint();
                        },
                  child: const Text('Hint'),
                ),
                Button(onPressed: s == null || s.finished ? null : s.showSolution, child: const Text('Show answer')),
                FilledButton(
                  onPressed: s != null && s.finished ? _next : null,
                  child: Text(_index + 1 < _queue.length ? 'Next card' : 'Finish'),
                ),
              ]),
      ),
    );
  }

  List<Widget> _status(Palette p, PuzzleSession s, StudyCard card) {
    final side = s.playerSide == Side.white ? 'White' : 'Black';
    final kind = switch (card.kind) {
      CardKind.opening => 'Repertoire',
      CardKind.lesson => 'Lesson exercise',
      CardKind.mistake => 'Your mistake',
      CardKind.puzzle => 'Missed puzzle',
    };
    final (text, tone) = switch (s.state) {
      PuzzleState.opponentMoving => ('Good. Watch the reply…', BubbleTone.move),
      PuzzleState.playerToMove => ('Find the best move for $side.', BubbleTone.info),
      PuzzleState.wrongMove => ('Not this one. Try again.', BubbleTone.warning),
      PuzzleState.solved => ('Correct!', BubbleTone.good),
      PuzzleState.showingSolution => ('Here is the answer.', BubbleTone.move),
    };
    return [
      Row(children: [
        Flexible(child: Pill(kind, color: card.kind == CardKind.mistake ? p.warning : p.accent)),
        const Spacer(),
        Text('${_index + 1} / ${_queue.length}', style: TextStyle(color: p.muted, fontSize: 12)),
      ]),
      const SizedBox(height: 10),
      Meter(_index / _queue.length),
      const SizedBox(height: 14),
      Text(card.title, style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 10),
      CoachBubble(text: text, tone: tone),
      if (_grade != null)
        Text(switch (_grade!) {
          Grade.again => 'You will see this one again soon.',
          Grade.hard => 'Solved with a hint: it comes back in a day or two.',
          Grade.good => 'It comes back in a few days.',
          Grade.easy => 'Quick and right: it comes back much later.',
        }, style: TextStyle(color: p.muted, fontSize: 12)),
    ];
  }

  List<Widget> _summary(Palette p) {
    final right = _grades.where((g) => g != Grade.again).length;
    return [
      Row(children: [
        Icon(FluentIcons.completed_solid, color: p.success, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(_grades.isEmpty ? 'Nothing to review right now' : 'Review finished',
              style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 12),
      CoachBubble(
        text: _grades.isEmpty
            ? 'Cards appear here after lessons (your repertoire moves), after reviewed games (your mistakes) '
                'and after puzzles you missed.'
            : 'You remembered $right of ${_grades.length}. Missed cards come back soon; the others when you are '
                'about to forget them.',
        tone: _grades.isEmpty ? BubbleTone.info : BubbleTone.good,
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(onPressed: () => Navigator.of(context).pop(_grades.length), child: const Text('Done')),
      ),
    ];
  }
}
