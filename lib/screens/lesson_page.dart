import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../app/board_sound.dart';
import '../app/board_style.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../data/curriculum.dart';
import '../data/event_store.dart';
import '../lessons/lesson.dart';
import '../lessons/progress.dart';
import '../puzzles/puzzle.dart';
import '../widgets/board_layout.dart';
import '../widgets/check_pulse.dart';
import '../widgets/common.dart';

/// Opens [lesson] where the player left off.
Future<void> openLesson(BuildContext context, Lesson lesson) {
  final progress = LessonProgress.fromEvents(StoreScope.read(context).events);
  return Navigator.of(context)
      .push(FluentPageRoute(builder: (_) => LessonPage(lesson: lesson, startStep: progress.resumeStep(lesson))));
}

/// Moves written out with move numbers, e.g. "4.Ng5 d5 5.exd5".
String formatMoves(Position start, Iterable<NormalMove> moves) {
  final out = StringBuffer();
  var pos = start;
  var first = true;
  for (final m in moves) {
    final (next, san) = pos.makeSan(m);
    if (pos.turn == Side.white) {
      out.write('${first ? '' : ' '}${pos.fullmoves}.$san');
    } else {
      out.write(first ? '${pos.fullmoves}...$san' : ' $san');
    }
    first = false;
    pos = next;
  }
  return out.toString();
}

/// Plays a lesson step by step: explanations with board demos, and
/// "find the move" exercises checked like puzzles.
class LessonPage extends StatefulWidget {
  const LessonPage({
    super.key,
    required this.lesson,
    this.startStep = 0,
    this.moveDelay = const Duration(milliseconds: 550),
    this.demoDelay = const Duration(milliseconds: 900),
  });

  final Lesson lesson;
  final int startStep;

  /// Pause before the opponent's reply in exercises.
  final Duration moveDelay;

  /// Pause between demo moves.
  final Duration demoDelay;

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  late final ChessboardController _board;
  late int _index;
  StepBoard? _step;
  String? _error;
  PuzzleSession? _session;
  bool? _firstTry;
  bool _hintShown = false;
  List<Position> _demo = const [];
  int _demoPly = 0;
  Timer? _demoTimer;
  bool _complete = false;
  final _recorded = <int>{};
  String _shownFen = '';

  Lesson get lesson => widget.lesson;
  LessonStep get _content => lesson.steps[_index];
  bool get _isFind => _content.kind == StepKind.find;
  bool get _last => _index == lesson.steps.length - 1;

  @override
  void initState() {
    super.initState();
    _board = ChessboardController(game: _gameData());
    _enter(widget.startStep.clamp(0, lesson.steps.length - 1));
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _session?.dispose();
    _board.dispose();
    super.dispose();
  }

  void _enter(int i) {
    _demoTimer?.cancel();
    _session?.removeListener(_onSession);
    _session?.dispose();
    _session = null;
    _lastState = null;
    _index = i;
    _firstTry = null;
    _hintShown = false;
    _demoPly = 0;
    _complete = false;
    try {
      _step = _content.resolve();
      _error = null;
    } catch (e) {
      _step = null;
      _error = 'This step could not be loaded ($e).';
    }
    final step = _step;
    _demo = step == null ? const [] : step.demoPositions;
    if (step != null && _isFind) {
      final session = PuzzleSession(
        PuzzleItem(
          id: 'lesson:${lesson.id}:$i',
          fen: step.start.fen,
          moves: step.solution,
          rating: lesson.level,
          themes: const [],
          setup: false,
        ),
        moveDelay: widget.moveDelay,
        onResult: (_, solved) => _firstTry = solved,
      );
      _session = session..addListener(_onSession);
      unawaited(session.start());
    } else if (_demo.length > 1) {
      _playDemo();
    }
    _refreshBoard(animate: false);
    if (mounted) setState(() {});
  }

  void _playDemo() {
    _demoTimer?.cancel();
    _demoPly = 0;
    _demoTimer = Timer.periodic(widget.demoDelay, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_demoPly >= _demo.length - 1) {
        t.cancel();
        return;
      }
      setState(() => _demoPly++);
      _refreshBoard(animate: true);
      final settings = SettingsScope.read(context);
      BoardSound.instance.play(_demo[_demoPly].isCheck ? BoardSoundKind.check : BoardSoundKind.move,
          soundOn: settings.boardSounds);
      if (_demoPly >= _demo.length - 1) t.cancel();
    });
  }

  void _onSession() {
    final s = _session;
    if (s != null) _playStateSound(s);
    _refreshBoard(animate: true);
    if (mounted) setState(() {});
  }

  /// The state at the last exercise change, for detecting transitions.
  PuzzleState? _lastState;

  /// Sounds for exercise transitions: right move, wrong move, check, solved.
  void _playStateSound(PuzzleSession s) {
    final state = s.state;
    final last = _lastState;
    _lastState = state;
    if (last == null) return;
    if (state == PuzzleState.wrongMove) {
      // Also on a repeated wrong try, where the state doesn't change.
      _exerciseSound(BoardSoundKind.capture, buzz: BuzzKind.thud);
      return;
    }
    if (state == last) return;
    switch (state) {
      case PuzzleState.solved:
        _exerciseSound(BoardSoundKind.victory);
      case PuzzleState.opponentMoving:
        // The player's move was correct.
        _exerciseSound(s.position.isCheck ? BoardSoundKind.check : BoardSoundKind.move,
            buzz: s.position.isCheck ? BuzzKind.alarm : BuzzKind.tap);
      case PuzzleState.playerToMove:
        // The opponent's reply to the player's correct move.
        if (last == PuzzleState.opponentMoving) {
          _exerciseSound(s.position.isCheck ? BoardSoundKind.check : BoardSoundKind.move);
        }
      case PuzzleState.wrongMove || PuzzleState.showingSolution:
        break;
    }
  }

  void _exerciseSound(BoardSoundKind kind, {BuzzKind? buzz}) {
    final settings = SettingsScope.read(context);
    BoardSound.instance.play(kind, soundOn: settings.boardSounds);
    if (buzz != null) BoardSound.instance.buzz(buzz, buzzOn: settings.haptics);
  }

  GameData _gameData() {
    final s = _session;
    if (s != null) {
      final pos = s.position;
      final canMove = s.state == PuzzleState.playerToMove || s.state == PuzzleState.wrongMove;
      return GameData(
        fen: pos.fen,
        lastMove: s.lastMove ?? _step?.lastMove,
        playerSide: canMove ? (s.playerSide == Side.white ? PlayerSide.white : PlayerSide.black) : PlayerSide.none,
        sideToMove: pos.turn,
        validMoves: canMove ? makeLegalMoves(pos) : const {},
        kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
      );
    }
    final pos = _demo.isEmpty ? Chess.initial : _demo[_demoPly];
    final step = _step;
    return GameData(
      fen: pos.fen,
      lastMove: step == null ? null : (_demoPly > 0 ? step.demo[_demoPly - 1] : step.lastMove),
      playerSide: PlayerSide.none,
      sideToMove: pos.turn,
      validMoves: const {},
      kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
    );
  }

  void _refreshBoard({required bool animate}) {
    final data = _gameData();
    _board.updatePosition(data, animate: animate && data.fen != _shownFen, resetPremove: true);
    _shownFen = data.fen;
  }

  /// The position the board shows right now (exercise or demo).
  Position get _shownPosition {
    final s = _session;
    if (s != null) return s.position;
    return _demo.isEmpty ? Chess.initial : _demo[_demoPly];
  }

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    final s = _session;
    if (s == null || move is! NormalMove) return;
    unawaited(s.playerMove(move).then((ok) {
      if (!ok && mounted) _refreshBoard(animate: false);
    }));
  }

  void _hint() {
    _session?.hint();
    setState(() => _hintShown = true);
  }

  void _record(int i) {
    if (!_recorded.add(i)) return;
    StoreScope.read(context).add(
          lessonEventType,
          lessonStepData(lesson, i, solved: _isFind ? (_firstTry ?? false) : null, done: _last),
        );
  }

  void _next() {
    _record(_index);
    if (_last) {
      _demoTimer?.cancel();
      setState(() => _complete = true);
    } else {
      _enter(_index + 1);
    }
  }

  bool get _canContinue {
    if (_error != null) return true;
    final s = _session;
    return s == null || s.finished;
  }

  Side get _orientation {
    final s = _session;
    if (s != null) return s.playerSide;
    return (lesson.asBlack != _content.flip) ? Side.black : Side.white;
  }

  Set<Shape> _shapes(Palette p) {
    final step = _step;
    if (step == null) return const {};
    final s = _session;
    final reveal = s == null ? _demoPly >= _demo.length - 1 : s.finished;
    final color = p.accent.withValues(alpha: 0.8);
    return {
      if (reveal) ...[
        for (final (a, b) in step.arrows) Arrow(color: color, orig: a, dest: b),
        for (final c in step.circles) Circle(color: color, orig: c),
      ],
      if (s?.hintSquare != null) Circle(color: p.success.withValues(alpha: 0.9), orig: s!.hintSquare!),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = SettingsScope.of(context);
    final style = BoardStyle.of(settings);
    final n = lesson.steps.length;
    // Keyboard: right arrow or Enter = Next, left arrow = Back.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _keyNext,
        const SingleActivator(LogicalKeyboardKey.enter): _keyNext,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (!_complete && _index > 0) _enter(_index - 1);
        },
      },
      child: Focus(autofocus: true, child: _page(p, style, settings, n)),
    );
  }

  void _keyNext() {
    if (!_complete && _canContinue) _next();
  }

  Widget _page(Palette p, BoardStyle style, AppSettings settings, int n) {
    return PageFrame(
      title: lesson.title,
      subtitle: _complete ? 'Lesson complete' : 'Step ${_index + 1} of $n · ${lesson.summary}',
      leading: const PageBackButton(),
      scroll: false,
      child: BoardLayout(
        boardLabel: _isFind
            ? 'Find the move. ${_orientation == Side.white ? 'White' : 'Black'} to play.'
            : 'Lesson board.',
        board: (size) => CheckPulse(
          size: size,
          orientation: _orientation,
          kingSquare: _shownPosition.isCheck ? _shownPosition.board.kingOf(_shownPosition.turn) : null,
          child: Chessboard(
            size: size,
            controller: _board,
            settings: style.settings(coordinates: settings.showCoordinates),
            orientation: _orientation,
            onMove: _onMove,
            shapes: _shapes(p),
          ),
        ),
        panel: SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: _complete ? _completePanel(p) : _stepPanel(p),
        ),
        actions: _complete ? null : _actions(),
      ),
    );
  }

  Widget _stepPanel(Palette p) {
    final n = lesson.steps.length;
    final s = _session;
    final step = _step;
    return ListView(children: [
      Row(children: [
        Flexible(child: Pill(_isFind ? 'Find the move' : 'Learn', color: _isFind ? p.warning : p.accent)),
        const Spacer(),
        Text('${_index + 1} / $n', style: TextStyle(color: p.muted, fontSize: 12)),
      ]),
      const SizedBox(height: 10),
      Meter((_index + (_canContinue ? 1 : 0)) / n),
      const SizedBox(height: 16),
      AnimatedSwitcher(
        duration: motion(context, const Duration(milliseconds: 250)),
        child: Text(_content.text,
            key: ValueKey(_index), style: TextStyle(color: p.text, fontSize: 15, height: 1.45)),
      ),
      const SizedBox(height: 14),
      if (_error != null) CoachBubble(text: _error!, tone: BubbleTone.warning),
      if (step != null && s == null && step.demo.isNotEmpty)
        CoachBubble(
          text: _demoPly < _demo.length - 1
              ? 'Watch: ${formatMoves(step.start, step.demo.take(_demoPly))}…'
              : formatMoves(step.start, step.demo),
          tone: BubbleTone.move,
        ),
      if (s != null) ..._findStatus(s, step!),
    ]);
  }

  List<Widget> _findStatus(PuzzleSession s, StepBoard step) {
    final side = s.playerSide == Side.white ? 'White' : 'Black';
    final hint = _content.hint;
    final playerMoves = [for (var i = 0; i < step.solutionSan.length; i += 2) step.solutionSan[i]];
    return [
      switch (s.state) {
        PuzzleState.opponentMoving => const CoachBubble(text: 'Good! Now watch the reply…', tone: BubbleTone.move),
        PuzzleState.playerToMove => CoachBubble(text: 'Your move as $side.'),
        PuzzleState.wrongMove => const CoachBubble(text: 'Not quite. Read the task again and try another move.',
            tone: BubbleTone.warning),
        PuzzleState.solved => CoachBubble(text: _content.success ?? 'Well done!', tone: BubbleTone.good),
        PuzzleState.showingSolution => CoachBubble(
            text: 'The answer: ${playerMoves.join(', then ')}. ${_content.success ?? ''}'.trim(),
            tone: BubbleTone.move),
      },
      if (_hintShown && hint != null && !s.finished) CoachBubble(text: 'Hint: $hint'),
    ];
  }

  Widget _completePanel(Palette p) {
    final progress = LessonProgress.fromEvents(StoreScope.of(context).events);
    final r = progress.records[lesson.id];
    final next = progress.next();
    return ListView(children: [
      Row(children: [
        Icon(FluentIcons.completed_solid, color: p.success, size: 22),
        const SizedBox(width: 10),
        Text('Lesson complete!', style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 12),
      if (r != null && r.tried > 0)
        CoachBubble(
          text: 'You found ${r.found} of ${r.tried} moves on the first try.',
          tone: r.found == r.tried ? BubbleTone.good : BubbleTone.info,
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        Button(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Back to lessons')),
        Button(onPressed: () => _enter(0), child: const Text('Repeat')),
        if (next != null)
          FilledButton(
            onPressed: () => Navigator.of(context).pushReplacement(FluentPageRoute(
                builder: (_) => LessonPage(lesson: next, startStep: progress.resumeStep(next)))),
            child: Text('Next: ${next.title}', overflow: TextOverflow.ellipsis),
          ),
      ]),
    ]);
  }

  Widget _actions() {
    final s = _session;
    final open = s != null && !s.finished && s.state != PuzzleState.opponentMoving;
    return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
      Button(
        onPressed: _index == 0 ? null : () => _enter(_index - 1),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(FluentIcons.chevron_left, size: 12),
          SizedBox(width: 6),
          Text('Back'),
        ]),
      ),
      if (s != null) ...[
        Button(
          onPressed: open ? _hint : null,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(FluentIcons.lightbulb, size: 14),
            SizedBox(width: 6),
            Text('Hint'),
          ]),
        ),
        Button(onPressed: open ? s.showSolution : null, child: const Text('Show answer')),
      ] else if (_demo.length > 1)
        Button(onPressed: _playDemo, child: const Text('Replay')),
      FilledButton(
        onPressed: _canContinue ? _next : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(_last ? 'Finish' : 'Next'),
          const SizedBox(width: 6),
          const Icon(FluentIcons.chevron_right, size: 12),
        ]),
      ),
    ]);
  }
}
