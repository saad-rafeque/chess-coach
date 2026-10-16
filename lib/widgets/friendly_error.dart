import 'package:fluent_ui/fluent_ui.dart';

/// Shown in place of a part of the screen that failed to build (release builds only).
class FriendlyError extends StatelessWidget {
  const FriendlyError({super.key});

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Something went wrong here. Your games and progress are safe; try another tab or restart the app.',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
          ),
        ),
      );
}
