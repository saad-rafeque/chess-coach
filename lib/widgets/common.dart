import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../app/theme.dart';

const mobileBreakpoint = 700.0;

bool isMobile(BuildContext context) => MediaQuery.sizeOf(context).width < mobileBreakpoint;

/// Page background (gradient, plus grain for the wooden theme) with a title header.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    required this.child,
    this.scroll = true,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Shown before the title, e.g. a back button.
  final Widget? leading;
  final Widget child;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final mobile = isMobile(context);
    final pad = mobile ? 16.0 : 32.0;
    final header = Padding(
      padding: EdgeInsets.fromLTRB(pad, mobile ? 16 : 28, pad, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: mobile ? 26 : 32,
                        fontWeight: FontWeight.w600,
                        color: p.text,
                        letterSpacing: -0.5)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: TextStyle(fontSize: 14, color: p.muted)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
    final body = Padding(padding: EdgeInsets.fromLTRB(pad, 0, pad, pad), child: child);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.background, p.backgroundEnd],
        ),
      ),
      child: CustomPaint(
        painter: p.woodGrain ? const _GrainPainter() : null,
        child: SafeArea(
          bottom: false,
          child: scroll
              ? ListView(padding: EdgeInsets.zero, children: [header, body])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, Expanded(child: body)],
                ),
        ),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var y = 0.0; y < size.height; y += 9 + rnd.nextDouble() * 10) {
      paint.color = const Color(0xFFFFE0B2).withValues(alpha: 0.015 + rnd.nextDouble() * 0.025);
      final path = Path()..moveTo(0, y);
      final amp = 2 + rnd.nextDouble() * 5;
      final phase = rnd.nextDouble() * math.pi * 2;
      for (var x = 0.0; x <= size.width; x += 24) {
        path.lineTo(x, y + math.sin(x / 140 + phase) * amp);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Rounded surface used for every card in the app.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap, this.highlight = false});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: p.woodGrain ? 0.88 : 1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? p.accent : p.border, width: highlight ? 1.6 : 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: p.brightness == Brightness.light ? 0.05 : 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return HoverButton(
      onPressed: onTap,
      builder: (context, states) => AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: states.isPressed ? 0.98 : 1,
        child: Opacity(opacity: states.isHovered ? 0.92 : 1, child: card),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: p.text)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Thin rounded progress bar.
class Meter extends StatelessWidget {
  const Meter(this.value, {super.key, this.color, this.height = 8});

  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(height: height, color: p.surfaceAlt),
          FractionallySizedBox(
            widthFactor: value.clamp(0, 1),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height),
                gradient: LinearGradient(colors: [
                  (color ?? p.accent).withValues(alpha: 0.75),
                  color ?? p.accent,
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = color ?? p.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
    );
  }
}

/// Wraps children in a responsive grid of equal-width columns.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minItemWidth = 220, this.spacing = 16});

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final fit = math.max(1, ((c.maxWidth + spacing) / (minItemWidth + spacing)).floor());
      final cols = math.min(fit, math.max(1, children.length));
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    });
  }
}
