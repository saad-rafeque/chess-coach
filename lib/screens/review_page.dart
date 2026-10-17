import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../app/board_style.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../widgets/friendly_text.dart';
import '../coach/coach_player.dart';
import '../data/event_store.dart';
import '../data/game_record.dart';
import '../engine/engine_host.dart';
import '../review/game_review.dart';
import '../review/guided_review.dart';
import '../train/skill_model.dart' show phaseOf;
import '../widgets/board_layout.dart';
import '../widgets/common.dart';

/// Opens the review of [game]; with [focus], the coach goes through those moves step by step.
Future<void> openReview(BuildContext context, GameRecord game, {ReviewFocus? focus}) =>
    Navigator.of(context).push(FluentPageRoute(builder: (_) => ReviewPage(game: game, focus: focus)));

Color qualityColor(Palette p, MoveQuality q) => switch (q) {
      MoveQuality.best => p.success,
      MoveQuality.good => p.accent,
      MoveQuality.inaccuracy => p.warning,
      MoveQuality.mistake => const Color(0xFFF97316),
      MoveQuality.blunder => p.danger,
    };

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.game, this.focus});

  final GameRecord game;

  /// Moves to go through with the coach as soon as the review is ready.
  final ReviewFocus? focus;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late final List<Position> _positions = widget.game.positions();
  late final List<String> _sans = widget.game.sans();
  GameReview? _review;
  (int, int)? _progress;
  String? _error;
  int _ply = 0;
  bool _showBetter = false;
  final _focus = FocusNode();

  /// The guided walkthrough: what it covers, its moves and the current step (steps.length = summary).
  ReviewFocus? _guide;
  List<ReviewedMove> _steps = const [];
  int _step = 0;

  /// Engine lines per ply: the better line, and what the played move allows.
  final _lines = <int, ({List<String> better, List<String> allows})>{};

  /// A line being played out on the board.
  ({List<Position> positions, List<Move> moves, int index})? _playback;
  Timer? _playTimer;

  @override
  void initState() {
    super.initState();
    _ply = _positions.length - 1;
    unawaited(_load());
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = StoreScope.read(context);
    final saved = store
        .ofType(GameAnalysis.eventType)
        .where((e) => e.data['game'] == widget.game.id)
        .lastOrNull;
    if (saved != null) {
      setState(() => _review = buildReview(widget.game, GameAnalysis.fromData(saved.data)));
      if (widget.focus != null) _startGuide(widget.focus!);
      return;
    }
    final engine = await EngineScope.of(context).engine;
    if (!mounted) return;
    if (engine == null) {
      setState(() => _error = 'Game review needs Stockfish, which isn\'t available on this device.');
      return;
    }
    setState(() => _progress = (0, _positions.length));
    final analysis = await analyseGame(engine, widget.game, onProgress: (done, total) {
      if (mounted) setState(() => _progress = (done, total));
    });
    await store.add(GameAnalysis.eventType, analysis.toData(widget.game.id));
    if (!mounted) return;
    setState(() => _review = buildReview(widget.game, analysis));
    if (widget.focus != null) _startGuide(widget.focus!);
  }

  void _go(int ply) {
    _stopPlayback();
    setState(() {
      _ply = ply.clamp(0, _positions.length - 1);
      _showBetter = false;
    });
  }

  void _startGuide(ReviewFocus focus) {
    final review = _review;
    if (review == null) return;
    setState(() {
      _guide = focus;
      _steps = guidedSteps(review, focus);
      _step = 0;
    });
    _showStep();
  }

  void _closeGuide() {
    _stopPlayback();
    setState(() {
      _guide = null;
      _showBetter = false;
    });
  }

  /// Moves the board to the current step: the position before the move, with the played and better moves.
  void _showStep() {
    _stopPlayback();
    if (_step >= _steps.length) {
      setState(() => _showBetter = false);
      return;
    }
    final m = _steps[_step];
    setState(() {
      _ply = m.ply + 1;
      _showBetter = m.bestUci != null;
    });
    unawaited(_loadLines(m));
  }

  void _stepBy(int delta) {
    setState(() => _step = (_step + delta).clamp(0, _steps.length));
    _showStep();
  }

  /// The better line and the reply to the played move: from the saved review at once, then longer
  /// lines from the engine when it's there.
  Future<void> _loadLines(ReviewedMove m) async {
    if (_lines.containsKey(m.ply)) return;
    final reply = m.ply + 1 < _review!.moves.length ? _review!.moves[m.ply + 1].bestUci : null;
    setState(() => _lines[m.ply] = (
          better: [if (m.bestUci != null) m.bestUci!],
          allows: [m.uci, if (reply != null) reply],
        ));
    final engine = await EngineScope.of(context).engine;
    if (engine == null || !mounted) return;
    try {
      final before = await engine.analyse(_positions[m.ply].fen, depth: 14);
      final after = await engine.analyse(_positions[m.ply + 1].fen, depth: 14);
      if (!mounted) return;
      final better = before.lines.firstOrNull?.pv ?? const <String>[];
      final allows = after.lines.firstOrNull?.pv ?? const <String>[];
      setState(() => _lines[m.ply] = (
            better: better.isEmpty ? _lines[m.ply]!.better : better.take(6).toList(),
            allows: allows.isEmpty ? _lines[m.ply]!.allows : [m.uci, ...allows.take(5)],
          ));
    } catch (_) {
      // The short lines from the saved review stay.
    }
  }

  /// Plays [uci] out on the board from [start], a move every second.
  void _play(Position start, List<String> uci) {
    _stopPlayback();
    final positions = [start];
    final moves = <Move>[];
    for (final u in uci) {
      final move = Move.parse(u);
      if (move == null || !positions.last.isLegal(move)) break;
      positions.add(positions.last.play(move));
      moves.add(move);
    }
    if (moves.isEmpty) return;
    setState(() => _playback = (positions: positions, moves: moves, index: 0));
    _playTimer = Timer.periodic(const Duration(milliseconds: 900), (t) {
      final pb = _playback;
      if (!mounted || pb == null) return t.cancel();
      setState(() => _playback = (positions: pb.positions, moves: pb.moves, index: pb.index + 1));
      if (pb.index + 1 >= pb.moves.length) t.cancel();
    });
  }

  void _stopPlayback() {
    _playTimer?.cancel();
    _playTimer = null;
    if (_playback != null && mounted) setState(() => _playback = null);
  }

  ReviewedMove? get _current => _review == null || _ply == 0 ? null : _review!.moves[_ply - 1];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = SettingsScope.of(context);
    final style = BoardStyle.of(s);
    final game = widget.game;
    final cur = _current;
    final pb = _playback;
    final showBetter = pb == null && _showBetter && cur != null && cur.bestUci != null;
    final boardPos = pb != null ? pb.positions[pb.index] : (showBetter ? _positions[_ply - 1] : _positions[_ply]);
    final shapes = <Shape>{
      if (showBetter) ...{
        if (Move.parse(cur.uci) case final NormalMove played)
          Arrow(
            color: (cur.quality.isError ? p.danger : p.accent).withValues(alpha: 0.75),
            orig: played.from,
            dest: played.to,
          ),
        if (cur.bestUci != cur.uci)
          if (Move.parse(cur.bestUci!) case final NormalMove best)
            Arrow(color: p.success.withValues(alpha: 0.85), orig: best.from, dest: best.to),
      },
    };
    final lastMove = pb != null
        ? (pb.index > 0 ? pb.moves[pb.index - 1] : null)
        : (!showBetter && _ply > 0 ? Move.parse(game.moves[_ply - 1]) : null);
    final phone = isMobile(context);
    final guide = _review == null ? null : _guideCard(p);
    final evalScore = _review == null
        ? null
        : (_ply == 0 ? _review!.moves.firstOrNull?.before : _review!.moves[_ply - 1].after);

    final when = '${game.date.day}/${game.date.month}/${game.date.year}';
    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is! KeyDownEvent) return;
        if (e.logicalKey == LogicalKeyboardKey.arrowLeft) _go(_ply - 1);
        if (e.logicalKey == LogicalKeyboardKey.arrowRight) _go(_ply + 1);
        if (e.logicalKey == LogicalKeyboardKey.home) _go(0);
        if (e.logicalKey == LogicalKeyboardKey.end) _go(_positions.length - 1);
      },
      child: PageFrame(
        title: 'Game review',
        subtitle: '${game.outcomeLabel} by ${game.ending} · You played ${game.playerSide == Side.white ? 'White' : 'Black'} '
            'vs ${SettingsScope.of(context).coachName} ~${game.coachElo} · $when',
        leading: const PageBackButton(),
        scroll: false,
      compactOnPhone: true,
        child: BoardLayout(
        panelTitle: 'Review',
          boardLabel: 'Game review, after ${_ply ~/ 2 + _ply % 2} moves.',
          overBoard: evalScore == null
              ? null
              : EvalBar(whitePercent: evalScore.whiteWinPercent, label: evalScore.label,
                  flipped: game.playerSide == Side.black),
          board: (size) => StaticChessboard(
            size: size,
            orientation: game.playerSide,
            fen: boardPos.fen,
            lastMove: lastMove,
            settings: style.staticSettings(coordinates: s.showCoordinates),
            shapes: shapes,
          ),
          actions: phone && guide != null
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _navButtons(),
                  Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 0), child: guide),
                ])
              : _navButtons(),
          panel: _panel(p, phone ? null : guide),
        ),
      ),
    );
  }

  /// The walkthrough: what to go through, then one move at a time, then the lesson to keep.
  Widget _guideCard(Palette p) {
    final review = _review!;
    final coach = SettingsScope.of(context).coachName;
    final guide = _guide;
    if (guide == null) {
      return _GuideFrame(
        title: 'Go through it with $coach',
        children: [
          Text('Pick what to look at. $coach shows what you played, what was better, where it leads and '
              'what to do next time.',
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
          const SizedBox(height: 10),
          for (final f in ReviewFocus.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _FocusButton(focus: f, count: guidedSteps(review, f).length, onPressed: () => _startGuide(f)),
            ),
        ],
      );
    }
    final n = _steps.length;
    if (_step >= n) {
      final lesson = mainLesson(_steps, _positions);
      final what = guide.label.toLowerCase();
      return _GuideFrame(
        title: n == 0 ? 'No $what in this game' : 'That\'s all your $what',
        onClose: _closeGuide,
        children: [
          Text(
            n == 0 ? 'Well played! Nothing to fix here.' : 'You went through $n ${n == 1 ? 'move' : 'moves'}.',
            style: TextStyle(color: p.text, height: 1.4),
          ),
          if (lesson != null) ...[
            const SizedBox(height: 12),
            _GuideSection(icon: FluentIcons.lightbulb, title: 'The lesson to keep', color: p.warning, text: lesson),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (n > 0) Button(onPressed: () => _stepBy(-1), child: const Text('Back')),
            for (final f in ReviewFocus.values)
              if (f != guide) Button(onPressed: () => _startGuide(f), child: Text(f.label)),
            FilledButton(onPressed: _closeGuide, child: const Text('Done')),
          ]),
        ],
      );
    }
    final m = _steps[_step];
    final before = _positions[m.ply];
    final lines = _lines[m.ply];
    final c = qualityColor(p, m.quality);
    final playing = _playback != null;
    Widget lineRow(String label, List<String>? uci, Position start, int ply) {
      final text = uci == null || uci.isEmpty ? null : sanLine(start, ply, uci);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Text(text == null ? label : '$label: $text',
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
        ),
        if (text != null)
          Tooltip(
            message: 'Play it on the board',
            child: IconButton(
              icon: Icon(FluentIcons.play, size: 14, color: p.accent, semanticLabel: 'Play $label'),
              onPressed: () => _play(start, uci!),
            ),
          ),
      ]);
    }

    return _GuideFrame(
      title: 'Step ${_step + 1} of $n',
      onClose: _closeGuide,
      children: [
        Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Move ${m.ply ~/ 2 + 1}: you played ${m.san}',
              style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w700)),
          Pill(m.quality.label, color: c),
        ]),
        const SizedBox(height: 10),
        if (m.quality.isError) ...[
          _GuideSection(
            icon: FluentIcons.warning,
            title: 'What happened',
            color: c,
            text: '${m.explanation ?? ''} ${chancesText(m)}'.trim(),
          ),
          if (m.bestSan != null) ...[
            const SizedBox(height: 10),
            _GuideSection(
              icon: FluentIcons.like,
              title: 'Better was ${m.bestSan}',
              color: p.success,
              child: lineRow('A likely line', lines?.better, before, m.ply),
            ),
          ],
          const SizedBox(height: 10),
          _GuideSection(
            icon: FluentIcons.flow,
            title: 'Where your move leads',
            color: p.danger,
            child: lineRow('Your move, then the best reply', lines?.allows, before, m.ply),
          ),
          if (m.errorKind != null) ...[
            const SizedBox(height: 10),
            _GuideSection(
              icon: FluentIcons.lightbulb,
              title: 'Next time',
              color: p.warning,
              text: nextTimeTip(m.errorKind!, phaseOf(before, m.ply)),
            ),
          ],
        ] else ...[
          _GuideSection(
            icon: FluentIcons.like,
            title: 'Good',
            color: p.success,
            text: '${goodMoveText(m)} ${chancesText(m)}',
          ),
          if (m.bestSan != null && m.bestSan != m.san) ...[
            const SizedBox(height: 10),
            lineRow('The engine\'s line', lines?.better, before, m.ply),
          ],
        ],
        const SizedBox(height: 12),
        Row(children: [
          if (playing)
            Button(onPressed: _showStep, child: const Text('Back to the move'))
          else
            Button(onPressed: _step == 0 ? null : () => _stepBy(-1), child: const Text('Previous')),
          const Spacer(),
          FilledButton(onPressed: () => _stepBy(1), child: Text(_step == n - 1 ? 'Finish' : 'Next')),
        ]),
      ],
    );
  }

  Widget _navButtons() {
    Widget b(IconData icon, String tip, int target) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Tooltip(
            message: tip,
            child: Button(
              onPressed: target == _ply || target < 0 || target >= _positions.length ? null : () => _go(target),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Icon(icon, size: 14)),
            ),
          ),
        );
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      b(FluentIcons.previous, 'Start', 0),
      b(FluentIcons.chevron_left, 'Previous move', _ply - 1),
      b(FluentIcons.chevron_right, 'Next move', _ply + 1),
      b(FluentIcons.next, 'End', _positions.length - 1),
    ]);
  }

  Widget _panel(Palette p, Widget? guide) {
    final review = _review;
    final game = widget.game;
    final children = <Widget>[];
    if (review == null) {
      children.add(_error != null
          ? CoachBubble(text: _error!, tone: BubbleTone.warning)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your coach is reviewing the game…', style: TextStyle(color: p.text)),
              const SizedBox(height: 10),
              Meter(_progress == null ? 0 : _progress!.$1 / _progress!.$2),
              const SizedBox(height: 6),
              Text(_progress == null ? 'Starting engine' : 'Position ${_progress!.$1} of ${_progress!.$2}',
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]));
    } else {
      final me = game.playerSide;
      children.addAll([
        Row(children: [
          Expanded(child: _Stat(label: 'Your accuracy', value: '${review.accuracy(me).round()}%', color: p.accent)),
          const SizedBox(width: 10),
          Expanded(
              child: _Stat(label: 'Coach accuracy', value: '${review.accuracy(me.opposite).round()}%', color: p.muted)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final q in [MoveQuality.blunder, MoveQuality.mistake, MoveQuality.inaccuracy])
            Pill(_plural(review.count(me, q), q), color: qualityColor(p, q)),
        ]),
        const SizedBox(height: 14),
        if (guide != null) ...[guide, const SizedBox(height: 14)],
      ]);
      final cur = _current;
      if (cur != null && _guide == null) {
        children.add(_MoveCard(
          move: cur,
          showBetter: _showBetter,
          onToggle: cur.quality.isError ? () => setState(() => _showBetter = !_showBetter) : null,
        ));
        children.add(const SizedBox(height: 14));
      }
      final key = review.keyMoments();
      children.add(Text('Key moments', style: TextStyle(color: p.text, fontWeight: FontWeight.w600)));
      children.add(const SizedBox(height: 6));
      if (key.isEmpty) {
        children.add(Text('No big mistakes in this game. Well played!', style: TextStyle(color: p.muted)));
      }
      for (final m in key) {
        children.add(HoverButton(
          onPressed: () => _go(m.ply + 1),
          builder: (context, states) => Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: states.isHovered || _ply == m.ply + 1 ? p.surfaceAlt : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: qualityColor(p, m.quality), shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Move ${m.ply ~/ 2 + 1}: ${m.san} (${m.quality.label.toLowerCase()})',
                    style: TextStyle(color: p.text)),
              ),
              Text('Best ${m.bestSan ?? '-'}', style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
        ));
      }
    }
    children.addAll([
      const SizedBox(height: 14),
      Text('Moves', style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(spacing: 2, runSpacing: 2, children: [
        for (var i = 0; i < _sans.length; i++) _moveChip(p, i),
      ]),
    ]);
    return SurfaceCard(padding: const EdgeInsets.all(16), child: ListView(children: children));
  }

  Widget _moveChip(Palette p, int i) {
    final q = _review?.moves[i].quality;
    final selected = _ply == i + 1;
    final color = q != null && q.isError ? qualityColor(p, q) : p.text;
    return HoverButton(
      onPressed: () => _go(i + 1),
      builder: (context, states) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? p.accent.withValues(alpha: 0.2) : (states.isHovered ? p.surfaceAlt : null),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('${i.isEven ? '${i ~/ 2 + 1}. ' : ''}${_sans[i]}',
            style: TextStyle(color: color, fontSize: 13, fontWeight: q != null && q.isError ? FontWeight.w600 : null)),
      ),
    );
  }
}

String _plural(int n, MoveQuality q) {
  final word = switch (q) {
    MoveQuality.inaccuracy => n == 1 ? 'inaccuracy' : 'inaccuracies',
    _ => n == 1 ? q.label.toLowerCase() : '${q.label.toLowerCase()}s',
  };
  return '$n $word';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: p.muted, fontSize: 12)),
        Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _MoveCard extends StatelessWidget {
  const _MoveCard({required this.move, required this.showBetter, required this.onToggle});

  final ReviewedMove move;
  final bool showBetter;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = qualityColor(p, move.quality);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${move.ply ~/ 2 + 1}${move.mover == Side.white ? '.' : '…'} ${move.san}',
                  style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w700)),
              Pill(move.quality.label, color: c),
            ]),
          ),
          Text(move.after.label, style: TextStyle(color: p.muted, fontSize: 12)),
        ]),
        if (move.explanation != null) ...[
          const SizedBox(height: 8),
          FriendlyText(move.explanation!, style: TextStyle(color: p.text, height: 1.4)),
        ],
        if (onToggle != null) ...[
          const SizedBox(height: 10),
          Button(
            onPressed: onToggle,
            child: Text(showBetter ? 'Back to the game' : 'Show the better move'),
          ),
        ],
      ]),
    );
  }
}

/// The walkthrough's card.
class _GuideFrame extends StatelessWidget {
  const _GuideFrame({required this.title, required this.children, this.onClose});

  final String title;
  final List<Widget> children;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.accent.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(FluentIcons.education, size: 16, color: p.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(color: p.text, fontWeight: FontWeight.w600))),
          if (onClose != null)
            Tooltip(
              message: 'Close the walkthrough',
              child: IconButton(icon: const Icon(FluentIcons.chrome_close, size: 11), onPressed: onClose),
            ),
        ]),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }
}

/// One part of a step: what happened, the better move, where it leads, next time.
class _GuideSection extends StatelessWidget {
  const _GuideSection({required this.icon, required this.title, required this.color, this.text, this.child});

  final IconData icon;
  final String title;
  final Color color;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 14, color: color)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 2),
          if (text != null) FriendlyText(text!, style: TextStyle(color: p.text, fontSize: 13, height: 1.4)),
          if (child != null) child!,
        ]),
      ),
    ]);
  }
}

/// "Blunders · 2": starts the walkthrough of one kind of move.
class _FocusButton extends StatelessWidget {
  const _FocusButton({required this.focus, required this.count, required this.onPressed});

  final ReviewFocus focus;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Button(
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(focus.label, style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
              Text(focus.detail, style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 8),
          Pill('$count', color: count == 0 ? p.success : p.accent),
          const SizedBox(width: 4),
          Icon(FluentIcons.chevron_right, size: 12, color: p.muted),
        ]),
      ),
    );
  }
}
