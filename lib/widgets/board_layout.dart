import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../app/theme.dart';
import 'common.dart';

/// Board with player bars on one side and a panel on the other (or below on phones).
class BoardLayout extends StatelessWidget {
  const BoardLayout({
    super.key,
    required this.board,
    required this.panel,
    this.top,
    this.bottom,
    this.actions,
  });

  final Widget Function(double size) board;
  final Widget panel;
  final Widget? top;
  final Widget? bottom;
  final Widget? actions;

  static const _barHeight = 52.0;
  static const _panelWidth = 380.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final mobile = c.maxWidth < mobileBreakpoint || c.maxWidth < c.maxHeight * 0.9;
      final bars = (top != null ? _barHeight : 0) + (bottom != null ? _barHeight : 0);
      if (!mobile) {
        final size = math.min(c.maxWidth - _panelWidth - 24, c.maxHeight - bars);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: size,
              child: Column(children: [
                if (top != null) SizedBox(height: _barHeight, child: top),
                board(size),
                if (bottom != null) SizedBox(height: _barHeight, child: bottom),
              ]),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: panel), if (actions != null) ...[const SizedBox(height: 12), actions!]],
              ),
            ),
          ],
        );
      }
      // Phones: board fills the width, everything below scrolls.
      final size = math.min(c.maxWidth, c.maxHeight * 0.62 - bars);
      final panelHeight = math.max(320.0, c.maxHeight - size - bars - 76);
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          if (top != null) SizedBox(height: _barHeight, child: top),
          Center(child: board(size)),
          if (bottom != null) SizedBox(height: _barHeight, child: bottom),
          if (actions != null) ...[const SizedBox(height: 4), actions!],
          const SizedBox(height: 12),
          SizedBox(height: panelHeight, child: panel),
        ],
      );
    });
  }
}

/// Name, rating and status shown above or below the board.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.name, required this.detail, required this.icon, this.active = false});

  final String name;
  final String detail;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: active ? p.accent : p.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: active ? p.onAccent : p.muted),
      ),
      const SizedBox(width: 10),
      Text(name, style: TextStyle(color: p.text, fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      Text(detail, style: TextStyle(color: p.muted, fontSize: 12)),
      const Spacer(),
      if (active)
        Text('to move', style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// Chat bubble from the coach (or the system).
class CoachBubble extends StatelessWidget {
  const CoachBubble({super.key, required this.text, this.tone = BubbleTone.info});

  final String text;
  final BubbleTone tone;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (color, icon) = switch (tone) {
      BubbleTone.info => (p.accent, FluentIcons.chat),
      BubbleTone.good => (p.success, FluentIcons.like),
      BubbleTone.warning => (p.warning, FluentIcons.warning),
      BubbleTone.move => (p.muted, FluentIcons.robot),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: tone == BubbleTone.move ? 0.08 : 0.12),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
          topLeft: Radius.circular(4),
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 14, color: color)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: p.text, height: 1.35))),
      ]),
    );
  }
}

enum BubbleTone { info, good, warning, move }

/// Two-option segmented switch.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        for (final e in options.entries)
          Expanded(
            child: HoverButton(
              onPressed: () => onChanged(e.key),
              builder: (context, states) => AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: e.key == value ? p.surface : null,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: e.key == value
                      ? [BoxShadow(color: const Color(0xFF000000).withValues(alpha: 0.12), blurRadius: 6)]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(e.value,
                    style: TextStyle(
                        color: e.key == value ? p.text : p.muted,
                        fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w400)),
              ),
            ),
          ),
      ]),
    );
  }
}
