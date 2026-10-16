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
import '../widgets/board_layout.dart';
import '../widgets/common.dart';

Future<void> openReview(BuildContext context, GameRecord game) =>
    Navigator.of(context).push(FluentPageRoute(builder: (_) => ReviewPage(game: game)));

Color qualityColor(Palette p, MoveQuality q) => switch (q) {
      MoveQuality.best => p.success,
      MoveQuality.good => p.accent,
      MoveQuality.inaccuracy => p.warning,
      MoveQuality.mistake => const Color(0xFFF97316),
      MoveQuality.blunder => p.danger,
    };

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.game});

  final GameRecord game;

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

  @override
  void initState() {
    super.initState();
    _ply = _positions.length - 1;
    unawaited(_load());
  }

  @override
  void dispose() {
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
    if (mounted) setState(() => _review = buildReview(widget.game, analysis));
  }

  void _go(int ply) => setState(() {
        _ply = ply.clamp(0, _positions.length - 1);
        _showBetter = false;
      });

  ReviewedMove? get _current => _review == null || _ply == 0 ? null : _review!.moves[_ply - 1];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = SettingsScope.of(context);
    final style = BoardStyle.forTheme(s.theme);
    final game = widget.game;
    final cur = _current;
    final showBetter = _showBetter && cur != null && cur.bestUci != null;
    final boardPos = showBetter ? _positions[_ply - 1] : _positions[_ply];
    final shapes = <Shape>{
      if (showBetter) ...{
        if (Move.parse(cur.uci) case final NormalMove played)
          Arrow(color: p.danger.withValues(alpha: 0.75), orig: played.from, dest: played.to),
        if (Move.parse(cur.bestUci!) case final NormalMove best)
          Arrow(color: p.success.withValues(alpha: 0.85), orig: best.from, dest: best.to),
      },
    };
    final lastMove = !showBetter && _ply > 0 ? Move.parse(game.moves[_ply - 1]) : null;
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
            'vs Coach ~${game.coachElo} · $when',
        leading: const PageBackButton(),
        scroll: false,
        child: BoardLayout(
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
          actions: _navButtons(),
          panel: _panel(p),
        ),
      ),
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

  Widget _panel(Palette p) {
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
      ]);
      final cur = _current;
      if (cur != null) {
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
          Text('${move.ply ~/ 2 + 1}${move.mover == Side.white ? '.' : '…'} ${move.san}',
              style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Pill(move.quality.label, color: c),
          const Spacer(),
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
