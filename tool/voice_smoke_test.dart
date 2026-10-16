// Runs the real explainer model on typical coach explanations and prints what it says.
// Run locally: MODEL=/path/to/qwen2.5-0.5b-instruct-q4_k_m.gguf flutter test tool/voice_smoke_test.dart
import 'dart:io';

import 'package:chess_coach/coach/llm/coach_voice.dart';
import 'package:flutter_test/flutter_test.dart';

const _facts = [
  'Now Black can take your knight on f6. Better was Nd5.',
  'This allows checkmate in 2. Better was Kh1.',
  'You missed Qxh7#, which wins.',
  'You missed Bxf7+, which wins a pawn.',
  'Now White can take your queen on d5. Better was Qe6.',
  'This makes your position clearly worse. Better was O-O.',
  'This loses a lot. Better was Rxe8+.',
  'There was a stronger move. Better was c5.',
];

void main() {
  test('real model rewords explanations safely', () async {
    final path = Platform.environment['MODEL'];
    if (path == null || !File(path).existsSync()) {
      markTestSkipped('Set MODEL to a downloaded GGUF file');
      return;
    }
    final watch = Stopwatch()..start();
    final g = await LlamaGenerator.load(File(path));
    stdout.writeln('loaded in ${watch.elapsedMilliseconds} ms');
    var accepted = 0;
    for (final f in _facts) {
      watch.reset();
      final raw = await g.generate(rephrasePrompt(f));
      final ok = acceptRephrase(f, raw);
      if (ok != null) accepted++;
      stdout.writeln('${watch.elapsedMilliseconds} ms | $f\n  -> $raw\n  ${ok == null ? 'REJECTED' : 'accepted'}');
    }
    stdout.writeln('$accepted / ${_facts.length} accepted');
    await g.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
