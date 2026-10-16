import 'dart:async';
import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../app/board_style.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../coach/preview_bot.dart';
import '../coach/quick_tips.dart';
import '../widgets/board_layout.dart';
import '../widgets/common.dart';

enum PlayMode { training, real }

class PlayPage extends StatefulWidget {
  const PlayPage({super.key});

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  final _rnd = math.Random();
  final _chatScroll = ScrollController();
  late final ChessboardController _board;

  /// Position after each ply; index 0 is the start.
  final _positions = <Position>[Chess.initial];
  final _moves = <Move>[];
  final _sans = <String>[];
  final _chat = <(String, BubbleTone)>[];
  PlayMode _mode = PlayMode.training;
  bool _flipped = false;
  bool _thinking = false;
  bool _resigned = false;

  Position get _pos => _positions.last;
  bool get _over => _resigned || _pos.isGameOver;

  @override
  void initState() {
    super.initState();
    _board = ChessboardController(game: _game());
    _greet();
  }

  @override
  void dispose() {
    _board.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  void _greet() {
    _chat
      ..add(('Hi! I\'m your coach. You play White. In Training mode I comment on every move.', BubbleTone.info))
      ..add(('Preview: for now I play as a simple practice bot. My human-like style arrives in milestone 2.',
          BubbleTone.move));
  }

  GameData _game() => GameData(
        fen: _pos.fen,
        lastMove: _moves.isEmpty ? null : _moves.last,
        playerSide: _over || _thinking ? PlayerSide.none : PlayerSide.white,
        sideToMove: _pos.turn,
        validMoves: makeLegalMoves(_pos),
        kingSquareInCheck: _pos.isCheck ? _pos.board.kingOf(_pos.turn) : null,
      );

  void _say(String text, BubbleTone tone) {
    _chat.add((text, tone));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _push(Move move) {
    final (after, san) = _pos.makeSan(move);
    _positions.add(after);
    _moves.add(move);
    _sans.add(san);
  }

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    if (move is! NormalMove || !_pos.isLegal(move)) return;
    final before = _pos;
    _push(move);
    final hints = _mode == PlayMode.training && SettingsScope.read(context).trainingHints;
    if (hints) {
      final tip = tipForMove(before, move, _pos);
      if (tip != null) {
        _say(tip.text, switch (tip.kind) {
          TipKind.good => BubbleTone.good,
          TipKind.warning => BubbleTone.warning,
          TipKind.info => BubbleTone.info,
        });
      }
    }
    setState(() {});
    _board.updatePosition(_game());
    if (_over) {
      _announceResult();
    } else {
      unawaited(_coachMove());
    }
  }

  Future<void> _coachMove() async {
    setState(() => _thinking = true);
    _board.updatePosition(_game());
    await Future<void>.delayed(Duration(milliseconds: 450 + _rnd.nextInt(500)));
    if (!mounted || _over) return;
    final move = pickPreviewMove(_pos, _rnd);
    final captured = _pos.board.pieceAt(move.to);
    _push(move);
    if (_mode == PlayMode.training) {
      final took = captured != null && captured.color == Side.white ? ', taking your ${captured.role.name}' : '';
      _say('I played ${_sans.last}$took.', BubbleTone.move);
    }
    setState(() => _thinking = false);
    _board.updatePosition(_game());
    if (_over) _announceResult();
  }

  void _announceResult() {
    final p = _pos;
    if (_resigned) {
      _say('You resigned. Every lost game is a lesson: the review will show the key moment.', BubbleTone.info);
    } else if (p.isCheckmate) {
      p.turn == Side.black
          ? _say('Checkmate! You won. Excellent finish.', BubbleTone.good)
          : _say('Checkmate. Let\'s learn from it: post-game review arrives in milestone 2.', BubbleTone.warning);
    } else {
      _say('The game is a draw.', BubbleTone.info);
    }
    setState(() {});
  }

  void _newGame() {
    setState(() {
      _positions
        ..clear()
        ..add(Chess.initial);
      _moves.clear();
      _sans.clear();
      _chat.clear();
      _resigned = false;
      _thinking = false;
      _greet();
    });
    _board.updatePosition(_game(), animate: false, resetPremove: true);
  }

  void _undo() {
    if (_thinking || _moves.isEmpty) return;
    final plies = _pos.turn == Side.white && _moves.length >= 2 ? 2 : 1;
    setState(() {
      for (var i = 0; i < plies; i++) {
        _positions.removeLast();
        _moves.removeLast();
        _sans.removeLast();
      }
      _resigned = false;
    });
    _board.updatePosition(_game(), animate: false);
    _say('Move taken back. Take your time and check for threats.', BubbleTone.info);
  }

  void _hint() {
    if (_over || _thinking) return;
    for (final m in legalMoves(_pos)) {
      final piece = freeCapture(_pos, m);
      if (piece != null) {
        setState(() => _say('Hint: Black\'s ${piece.role.name} on ${m.to.name} is not defended.', BubbleTone.info));
        return;
      }
    }
    setState(() => _say(
        'Hint: no free material right now. Develop a piece, control the centre or improve your king\'s safety.',
        BubbleTone.info));
  }

  void _resign() {
    if (_over || _moves.isEmpty) return;
    setState(() => _resigned = true);
    _board.updatePosition(_game());
    _announceResult();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = SettingsScope.of(context);
    final style = BoardStyle.forTheme(s.theme);
    final coachBar = PlayerBar(
        name: 'Coach', detail: 'practice bot', icon: FluentIcons.robot, active: !_over && _pos.turn == Side.black);
    final youBar = PlayerBar(
        name: 'You', detail: '~750', icon: FluentIcons.contact, active: !_over && _pos.turn == Side.white);

    final panel = SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Segmented<PlayMode>(
            options: const {PlayMode.training: 'Training', PlayMode.real: 'Real game'},
            value: _mode,
            onChanged: (m) => setState(() {
              _mode = m;
              _say(
                  m == PlayMode.training
                      ? 'Training mode: I\'ll comment on your moves.'
                      : 'Real game: I\'ll stay quiet until the game ends.',
                  BubbleTone.info);
            }),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Text('Coach', style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (_thinking) const SizedBox(width: 14, height: 14, child: ProgressRing(strokeWidth: 2)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: _chatScroll,
              itemCount: _chat.length,
              itemBuilder: (context, i) => CoachBubble(text: _chat[i].$1, tone: _chat[i].$2),
            ),
          ),
          const SizedBox(height: 8),
          Text('Moves', style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            height: 64,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(
              reverse: true,
              child: Text(
                _sans.isEmpty ? 'No moves yet' : _moveText(),
                style: TextStyle(color: _sans.isEmpty ? p.muted : p.text, fontSize: 13, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );

    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final a in [
          _Action(icon: FluentIcons.add, label: 'New', onPressed: _newGame),
          _Action(icon: FluentIcons.undo, label: 'Undo', onPressed: _moves.isEmpty || _thinking ? null : _undo),
          _Action(icon: FluentIcons.lightbulb, label: 'Hint', onPressed: _over ? null : _hint),
          _Action(icon: FluentIcons.sync, label: 'Flip', onPressed: () => setState(() => _flipped = !_flipped)),
          _Action(icon: FluentIcons.flag, label: 'Resign', onPressed: _over || _moves.isEmpty ? null : _resign),
        ])
          Flexible(child: a),
      ],
    );

    return PageFrame(
      title: 'Play',
      subtitle: isMobile(context) ? null : 'Play the coach and learn from every move',
      scroll: false,
      child: BoardLayout(
        top: _flipped ? youBar : coachBar,
        bottom: _flipped ? coachBar : youBar,
        actions: actions,
        board: (size) => Chessboard(
          size: size,
          controller: _board,
          settings: style.settings(coordinates: s.showCoordinates),
          orientation: _flipped ? Side.black : Side.white,
          onMove: _onMove,
        ),
        panel: panel,
      ),
    );
  }

  String _moveText() {
    final b = StringBuffer();
    for (var i = 0; i < _sans.length; i++) {
      if (i.isEven) b.write('${i ~/ 2 + 1}. ');
      b.write('${_sans[i]}  ');
    }
    return b.toString().trimRight();
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: label,
        child: Button(
          onPressed: onPressed,
          style: ButtonStyle(
              padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: isMobile(context) ? 6 : 12, vertical: 8))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: onPressed == null ? p.muted.withValues(alpha: 0.5) : p.text),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: onPressed == null ? p.muted.withValues(alpha: 0.5) : p.muted)),
          ]),
        ),
      ),
    );
  }
}
