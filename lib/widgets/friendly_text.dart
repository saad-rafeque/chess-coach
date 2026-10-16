import 'package:fluent_ui/fluent_ui.dart';

import '../coach/llm/coach_voice.dart';

/// Shows [text] at once and swaps in the coach voice's friendlier wording if it arrives.
class FriendlyText extends StatefulWidget {
  const FriendlyText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<FriendlyText> createState() => _FriendlyTextState();
}

class _FriendlyTextState extends State<FriendlyText> {
  String? _friendly;
  String? _asked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ask();
  }

  @override
  void didUpdateWidget(FriendlyText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _ask();
  }

  void _ask() {
    final text = widget.text;
    if (_asked == text) return;
    _asked = text;
    _friendly = null;
    VoiceScope.of(context).polish(text).then((v) {
      if (mounted && _asked == text && v != null) setState(() => _friendly = v);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(_friendly ?? widget.text, key: ValueKey(_friendly ?? widget.text), style: widget.style),
      );
}
