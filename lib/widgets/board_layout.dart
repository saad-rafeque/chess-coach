import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;

import '../app/settings.dart';
import '../app/picture_in_picture.dart';
import '../app/theme.dart';
import 'common.dart';

/// Board with player bars on one side and a panel on the other.
///
/// Phones: the board spans the whole screen width, centred on the free space, with the panel
/// behind a slide-up sheet (a slim peek stays under the board when the player chose to keep it
/// there; pages that need the panel, like lessons, keep it right under the board).
/// Desktop: the panel sits beside the board and can be hidden with the dock button, so the
/// board takes the whole window, centred.
class BoardLayout extends StatefulWidget {
  const BoardLayout({
    super.key,
    required this.board,
    required this.panel,
    this.top,
    this.bottom,
    this.actions,
    this.overBoard,
    this.boardLabel,
    this.panelTitle,
    this.peek,
    this.compactMessage,
    this.compactHint,
    this.compactActionLabel = 'Hint',
    this.portraitHeader,
  });

  final Widget Function(double size) board;
  final Widget panel;
  final Widget? top;
  final Widget? bottom;
  final Widget? actions;

  /// Phones: a compact strip under the board instead of the panel button
  /// (e.g. the coach's latest message); tapping it opens the panel.
  final Widget? peek;

  /// Latest coach text for short split-screen and PiP layouts.
  final String? compactMessage;

  /// Optional primary action beside the coach strip in short layouts.
  final VoidCallback? compactHint;
  final String compactActionLabel;

  /// Game status and moves above a centred portrait board. Learning pages keep
  /// their scrolling layout when they need a longer lesson panel.
  final Widget? portraitHeader;

  /// Slim strip directly above the board (the evaluation bar).
  final Widget? overBoard;

  /// What screen readers announce for the board, e.g. "Puzzle. White to move."
  final String? boardLabel;

  /// Name of the panel's button on phones (e.g. "Coach"). Null keeps the panel under the board.
  final String? panelTitle;

  @override
  State<BoardLayout> createState() => _BoardLayoutState();
}

class _BoardLayoutState extends State<BoardLayout> {
  bool _sheet = false;
  bool _panelHidden = false;
  final _boardKey = GlobalKey(debugLabel: 'adaptive-board');

  Widget _board(double size) => Semantics(
    key: _boardKey,
    container: true,
    label: widget.boardLabel,
    child: RepaintBoundary(
      child: SizedBox.square(dimension: size, child: widget.board(size)),
    ),
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: PictureInPicture.active,
    builder: (context, pip, _) => PopScope(
      canPop: !_sheet,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _sheet) setState(() => _sheet = false);
      },
      child: LayoutBuilder(
        builder: (context, c) {
          if (pip) return _pip(c);
          final short = c.maxHeight < 500 && widget.panelTitle != null;
          final wide = c.maxWidth >= 600 && c.maxWidth > c.maxHeight * 1.25;
          final sidePanel = wide && !_panelHidden;
          final panelWidth = (c.maxWidth * 0.34).clamp(240.0, 340.0);
          if (short) {
            // A narrow split keeps a square board and readable coach; landscape
            // uses spare horizontal space rather than shrinking everything.
            final beside = c.maxWidth > c.maxHeight * 1.35;
            if (beside) {
              final size = math.max(
                1.0,
                math.min(c.maxHeight, c.maxWidth * 0.56),
              );
              return Stack(
                children: [
                  Row(
                    children: [
                      _board(size),
                      const SizedBox(width: 10),
                      Expanded(child: _compactCoach(actions: true)),
                    ],
                  ),
                  if (_sheet) _sheetOverlay(c),
                ],
              );
            }
            final footer = math.min(64.0, c.maxHeight * 0.25);
            final size = math.max(
              1.0,
              math.min(c.maxWidth, c.maxHeight - footer),
            );
            return Stack(
              children: [
                Column(
                  children: [
                    Expanded(child: Center(child: _board(size))),
                    SizedBox(
                      height: footer,
                      child: Row(
                        children: [
                          Expanded(child: _coachStrip(lines: 1)),
                          if (widget.compactHint != null)
                            FilledButton(
                              onPressed: widget.compactHint,
                              child: Text(widget.compactActionLabel),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_sheet) _sheetOverlay(c),
              ],
            );
          }
          if (wide) {
            final available = sidePanel
                ? c.maxWidth - panelWidth - 16
                : c.maxWidth;
            final bars =
                (widget.top == null ? 0.0 : 40.0) +
                (widget.bottom == null ? 0.0 : 40.0) +
                (widget.overBoard == null ? 0.0 : 14.0) +
                32 +
                (_panelHidden && widget.actions != null ? 60 : 0);
            final size = math.max(1.0, math.min(available, c.maxHeight - bars));
            final column = SizedBox(
              width: size,
              child: Column(
                children: [
                  SizedBox(
                    height: 32,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Tooltip(
                        message: _panelHidden
                            ? 'Show coach panel'
                            : 'Focus on board',
                        child: IconButton(
                          icon: Icon(
                            _panelHidden
                                ? FluentIcons.dock_right
                                : FluentIcons.dock_left,
                            size: 16,
                          ),
                          onPressed: () =>
                              setState(() => _panelHidden = !_panelHidden),
                        ),
                      ),
                    ),
                  ),
                  if (widget.top != null)
                    SizedBox(height: 40, child: widget.top),
                  if (widget.overBoard != null)
                    SizedBox(height: 14, child: widget.overBoard),
                  _board(size),
                  if (widget.bottom != null)
                    SizedBox(height: 40, child: widget.bottom),
                  if (_panelHidden && widget.actions != null)
                    SizedBox(height: 60, child: widget.actions),
                ],
              ),
            );
            return Row(
              children: [
                Expanded(child: Center(child: column)),
                if (sidePanel) ...[
                  const SizedBox(width: 16),
                  SizedBox(
                    width: panelWidth,
                    child: Column(
                      children: [
                        Expanded(child: widget.panel),
                        if (widget.actions != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: widget.actions!,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          }
          final under =
              widget.panelTitle == null ||
              SettingsScope.of(context).panelUnderBoard;
          final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
          // Reserve equal bands around the board, then place the opponent at
          // the bottom of the upper band and the player at the top of the lower
          // band. This centres the board itself, rather than the whole column.
          final band = (c.maxHeight - c.maxWidth) / 2;
          final minBand = 156.0 + math.max(0.0, textScale - 1) * 220;
          if (widget.portraitHeader != null && !under && band >= minBand) {
            return Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 4),
                            widget.portraitHeader!,
                            const Spacer(),
                            if (widget.top != null)
                              SizedBox(height: 40, child: widget.top),
                            // Keep the board stationary when evaluation arrives.
                            SizedBox(height: 14, child: widget.overBoard),
                          ],
                        ),
                      ),
                    ),
                    _board(c.maxWidth),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.bottom != null)
                              SizedBox(height: 40, child: widget.bottom),
                            if (widget.actions != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: widget.actions!,
                              ),
                            const Spacer(),
                            _coachStrip(
                              lines: widget.bottom == null
                                  ? (band >= 200 ? 4 : 3)
                                  : (band >= 178 ? 2 : 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_sheet) _sheetOverlay(c),
              ],
            );
          }
          // Portrait boards use the full available width. Controls and learning
          // content scroll on small phones and at large font sizes.
          final size = c.maxWidth;
          Widget inset(Widget child) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: child,
          );
          return Stack(
            children: [
              ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (widget.portraitHeader != null)
                    inset(
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: widget.portraitHeader!,
                      ),
                    ),
                  if (widget.top != null)
                    inset(SizedBox(height: 44, child: widget.top)),
                  if (widget.overBoard != null)
                    SizedBox(height: 14, child: widget.overBoard),
                  _board(size),
                  if (widget.bottom != null)
                    inset(SizedBox(height: 44, child: widget.bottom)),
                  if (widget.actions != null)
                    inset(
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: widget.actions!,
                      ),
                    ),
                  if (under)
                    inset(
                      SizedBox(
                        height: math.max(260.0, c.maxHeight - size - 160),
                        child: widget.panel,
                      ),
                    )
                  else
                    inset(_coachStrip()),
                  const SizedBox(height: 12),
                ],
              ),
              if (_sheet) _sheetOverlay(c),
            ],
          );
        },
      ),
    ),
  );

  Widget _coachStrip({int lines = 3}) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      label: 'Open ${widget.panelTitle} suggestions',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _sheet = true),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: p.glassDecoration(radius: 22, highlight: true),
          child: Row(
            children: [
              Container(
                width: lines == 1 ? 20 : 32,
                height: lines == 1 ? 20 : 32,
                decoration: p.glassDecoration(
                  radius: 12,
                  highlight: true,
                  subtle: true,
                ),
                child: Icon(FluentIcons.robot, color: p.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: lines == 1
                    ? Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.panelTitle ?? 'Coach',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.compactMessage ?? 'Open coach',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.text, fontSize: 13),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.panelTitle ?? 'Coach',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.compactMessage ?? 'Open your coach',
                            maxLines: lines,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.text,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 6),
              Icon(FluentIcons.chevron_up, size: 12, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactCoach({bool actions = false}) {
    final p = Palette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.panelTitle ?? 'Coach',
            style: TextStyle(color: p.accent, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            widget.compactMessage ?? 'Ask for a hint when it is your turn.',
            maxLines: actions ? 3 : null,
            overflow: actions ? TextOverflow.ellipsis : null,
            style: TextStyle(color: p.text, fontSize: 13, height: 1.4),
          ),
          if (widget.compactHint != null &&
              (!actions || widget.actions == null))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton(
                onPressed: widget.compactHint,
                child: Text(widget.compactActionLabel),
              ),
            ),
          if (actions && widget.actions != null) widget.actions!,
          if (actions)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Button(
                onPressed: () => setState(() => _sheet = true),
                child: Text('Open ${widget.panelTitle ?? 'details'}'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pip(BoxConstraints c) {
    final p = Palette.of(context);
    final size = math.max(1.0, math.min(c.maxHeight, c.maxWidth * 0.43));
    return ColoredBox(
      color: p.background,
      child: Row(
        children: [
          IgnorePointer(child: _board(size)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: LayoutBuilder(
                builder: (context, text) {
                  final scale = MediaQuery.textScalerOf(context);
                  final lines = math.max(
                    1,
                    ((text.maxHeight - scale.scale(16) - 4) / scale.scale(17))
                        .floor(),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.panelTitle ?? 'Coach',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          widget.compactMessage ?? 'Ready for your next move.',
                          maxLines: lines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.text,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetOverlay(BoxConstraints c) {
    final p = Palette.of(context);
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x88000000),
        child: Column(
          children: [
            Expanded(
              flex: 1,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _sheet = false),
              ),
            ),
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.background,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(
                          FluentIcons.chrome_close,
                          size: 18,
                          semanticLabel: 'Close coach panel',
                        ),
                        onPressed: () => setState(() => _sheet = false),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, inner) {
                          return SingleChildScrollView(
                            child: Column(
                              children: [
                                SizedBox(
                                  height: math.max(
                                    320,
                                    inner.maxHeight -
                                        (widget.actions == null ? 0 : 76),
                                  ),
                                  child: widget.panel,
                                ),
                                if (widget.actions != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: widget.actions!,
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name, rating, captured pieces, and status shown above or below the board.
class PlayerBar extends StatelessWidget {
  const PlayerBar({
    super.key,
    required this.name,
    required this.detail,
    required this.icon,
    this.active = false,
    this.capturedPieces,
    this.advantage,
    this.badge,
    this.clock,
  });

  final String name;
  final String detail;
  final IconData icon;
  final bool active;
  final List<String>? capturedPieces;
  final int? advantage;
  final String? badge;
  final String? clock;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: p.glassDecoration(
        radius: 18,
        highlight: active,
        subtle: true,
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: motion(context, const Duration(milliseconds: 200)),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              gradient: active
                  ? LinearGradient(
                      colors: [
                        p.accent,
                        Color.lerp(p.accent, Colors.white, 0.25)!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: active ? null : p.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? p.accent : p.glassBorderSubtle,
                width: 1,
              ),
              boxShadow: [
                if (active)
                  BoxShadow(
                    color: p.accent.withValues(alpha: 0.35),
                    blurRadius: 8,
                    spreadRadius: 0.5,
                  ),
              ],
            ),
            child: Icon(icon, size: 15, color: active ? p.onAccent : p.muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: p.accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: p.accent.withValues(alpha: 0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                badge!,
                                style: TextStyle(
                                  color: p.accent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.brightness == Brightness.dark
                                    ? const Color(0xFFCBD5E1)
                                    : p.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if ((capturedPieces != null &&
                              capturedPieces!.isNotEmpty) ||
                          (advantage != null && advantage! > 0)) ...[
                        const SizedBox(height: 1),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (capturedPieces != null &&
                                capturedPieces!.isNotEmpty)
                              Flexible(
                                child: Text(
                                  capturedPieces!.join(''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.text.withValues(alpha: 0.85),
                                    height: 1.0,
                                  ),
                                ),
                              ),
                            if (advantage != null && advantage! > 0) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 0.5,
                                ),
                                decoration: BoxDecoration(
                                  color: p.accent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '+$advantage',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: p.accent,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (clock != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: active
                    ? (p.brightness == Brightness.dark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFF0F172A))
                    : p.glassFillSubtle,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: active ? p.accent : p.glassBorderSubtle,
                  width: active ? 1.5 : 1.0,
                ),
                boxShadow: [
                  if (active)
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.25),
                      blurRadius: 8,
                    ),
                ],
              ),
              child: Text(
                clock!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? (p.brightness == Brightness.dark
                            ? Colors.white
                            : const Color(0xFFF8FAFC))
                      : p.muted,
                ),
              ),
            )
          else if (active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: p.accent.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: p.accent, blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'to move',
                    style: TextStyle(
                      color: p.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The colour and icon of a [CoachBubble] tone.
(Color, IconData) bubbleStyle(Palette p, BubbleTone tone) => switch (tone) {
  BubbleTone.info => (p.accent, FluentIcons.chat),
  BubbleTone.good => (p.success, FluentIcons.like),
  BubbleTone.warning => (p.warning, FluentIcons.warning),
  BubbleTone.move => (p.muted, FluentIcons.robot),
};

/// Chat bubble from the coach (or the system).
class CoachBubble extends StatelessWidget {
  const CoachBubble({
    super.key,
    required this.text,
    this.tone = BubbleTone.info,
  });

  final String text;
  final BubbleTone tone;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (color, icon) = bubbleStyle(p, tone);
    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: tone == BubbleTone.move ? 0.08 : 0.12),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
          topLeft: Radius.circular(8),
        ),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: p.text, height: 1.35)),
          ),
        ],
      ),
    );
    // New messages fade and slide in (skipped when the system asks for less motion).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion(context, const Duration(milliseconds: 260)),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: bubble,
    );
  }
}

enum BubbleTone { info, good, warning, move }

/// One compact chat line for the strip under the board on phones; the whole
/// strip opens the full panel.
class PeekBubble extends StatelessWidget {
  const PeekBubble({
    super.key,
    required this.text,
    this.tone = BubbleTone.info,
  });

  final String text;
  final BubbleTone tone;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (color, icon) = bubbleStyle(p, tone);
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.text, fontSize: 13, height: 1.3),
          ),
        ),
        const SizedBox(width: 8),
        Icon(FluentIcons.chevron_up, size: 12, color: p.muted),
      ],
    );
  }
}

/// Thin horizontal bar: White's share of the winning chances.
class EvalBar extends StatelessWidget {
  const EvalBar({
    super.key,
    required this.whitePercent,
    required this.label,
    this.flipped = false,
  });

  final double whitePercent;
  final String label;

  /// True when the board shows Black at the bottom (bar fills from the right).
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final share = (whitePercent / 100).clamp(0.02, 0.98);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(color: const Color(0xFF1E222A)),
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.easeOutCubic,
                    alignment: flipped
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    widthFactor: share,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        boxShadow: [
                          BoxShadow(color: Color(0x33FFFFFF), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: p.glassFillSubtle,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: p.glassBorderSubtle),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Two-option segmented switch.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    if (p.interfaceStyle == InterfaceStyle.material) {
      return material.Theme(
        data: material.ThemeData(
          useMaterial3: true,
          brightness: p.brightness,
          colorScheme: material.ColorScheme.fromSeed(
            seedColor: p.accent,
            brightness: p.brightness,
          ),
        ),
        child: material.Material(
          type: material.MaterialType.transparency,
          child: material.SegmentedButton<T>(
            expandedInsets: EdgeInsets.zero,
            showSelectedIcon: false,
            segments: [
              for (final e in options.entries)
                material.ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {value},
            onSelectionChanged: (selection) => onChanged(selection.single),
            style: material.SegmentedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              tapTargetSize: material.MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              foregroundColor: p.muted,
              selectedForegroundColor: p.onAccent,
              selectedBackgroundColor: p.accent,
              backgroundColor: p.surface,
            ),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: p.glassDecoration(radius: 24, subtle: true),
      child: Row(
        children: [
          for (final e in options.entries)
            Expanded(
              child: HoverButton(
                onPressed: () => onChanged(e.key),
                builder: (context, states) => AnimatedContainer(
                  duration: motion(context, const Duration(milliseconds: 160)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: e.key == value
                      ? p.glassDecoration(radius: 20, highlight: true)
                      : BoxDecoration(
                          color: states.isHovered
                              ? p.glassFillSubtle
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                  alignment: Alignment.center,
                  child: Text(
                    e.value,
                    style: TextStyle(
                      color: e.key == value ? p.accent : p.muted,
                      fontWeight: e.key == value
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
