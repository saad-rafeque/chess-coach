import 'package:flutter/widgets.dart';

/// Original geometric knight, shared by the launcher and in-app branding.
class CoachMark extends StatelessWidget {
  const CoachMark({
    super.key,
    this.foregroundOnly = false,
    this.backgroundOnly = false,
  });
  final bool foregroundOnly;
  final bool backgroundOnly;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _MarkPainter(foregroundOnly, backgroundOnly),
    child: const SizedBox.expand(),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.foregroundOnly, this.backgroundOnly);
  final bool foregroundOnly;
  final bool backgroundOnly;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    if (!foregroundOnly) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 64, 64),
          Radius.circular(backgroundOnly ? 0 : 14),
        ),
        Paint()..color = const Color(0xFF668F3C),
      );
    }
    if (backgroundOnly) return;
    if (foregroundOnly) {
      canvas.translate(10, 10);
      canvas.scale(0.69);
    }
    final knight = Path()
      ..moveTo(18, 46)
      ..lineTo(45, 46)
      ..lineTo(42, 41)
      ..lineTo(32, 38)
      ..cubicTo(33, 32, 46, 29, 46, 21)
      ..cubicTo(46, 14, 40, 10, 32, 11)
      ..lineTo(28, 6)
      ..lineTo(25, 14)
      ..lineTo(18, 21)
      ..lineTo(14, 29)
      ..lineTo(23, 33)
      ..lineTo(29, 27)
      ..cubicTo(29, 33, 19, 36, 18, 42)
      ..close();
    final ivory = Paint()..color = const Color(0xFFF7F4E7);
    canvas.drawPath(knight, ivory);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(16, 49, 32, 6),
        const Radius.circular(2),
      ),
      ivory,
    );
    canvas.drawCircle(
      const Offset(32, 20),
      1.8,
      Paint()..color = const Color(0xFF344C22),
    );
    canvas.drawPath(
      Path()
        ..moveTo(37, 15)
        ..quadraticBezierTo(44, 22, 37, 28),
      Paint()
        ..color = const Color(0xFF668F3C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.foregroundOnly != foregroundOnly ||
      old.backgroundOnly != backgroundOnly;
}
