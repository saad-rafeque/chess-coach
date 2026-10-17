import 'package:chess_coach/app/board_sound.dart';
import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/widgets/check_pulse.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settings', () {
    test('sounds and haptics are on by default and can be switched off', () {
      final s = AppSettings.memory();
      expect(s.boardSounds, isTrue);
      expect(s.haptics, isTrue);
      s.boardSounds = false;
      s.haptics = false;
      expect(s.boardSounds, isFalse);
      expect(s.haptics, isFalse);
    });
  });

  group('board sounds', () {
    test('no audio device or haptics service: every call stays silent and never throws', () async {
      // Tests run without the audio and haptics plugins; the service must swallow that.
      BoardSound.instance.play(BoardSoundKind.move, soundOn: false);
      BoardSound.instance.play(BoardSoundKind.move, soundOn: true);
      BoardSound.instance.play(BoardSoundKind.capture, soundOn: true);
      BoardSound.instance.play(BoardSoundKind.check, soundOn: true);
      BoardSound.instance.play(BoardSoundKind.victory, soundOn: true);
      BoardSound.instance.play(BoardSoundKind.defeat, soundOn: true);
      BoardSound.instance.buzz(BuzzKind.tap, buzzOn: true);
      BoardSound.instance.buzz(BuzzKind.thud, buzzOn: true);
      BoardSound.instance.buzz(BuzzKind.alarm, buzzOn: true);
      // Give the audio futures a chance to fail; the test itself then proves
      // that no unhandled error escaped.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });

  group('check pulse', () {
    Future<void> pumpPulse(WidgetTester tester, {required Side orientation, Square? king}) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: CheckPulse(
            size: 320,
            orientation: orientation,
            kingSquare: king,
            child: const SizedBox(width: 320, height: 320),
          ),
        ),
      ));
    }

    // The glow overlay; the only IgnorePointer that actually ignores events
    // (the framework adds its own non-ignoring ones).
    final glow = find.byWidgetPredicate((w) => w is IgnorePointer && w.ignoring);

    testWidgets('marks the checked king square and follows the orientation', (tester) async {
      // e1: file 4, rank 0. Viewed from White the square sits at (4*40, 7*40).
      await pumpPulse(tester, orientation: Side.white, king: Square.fromCoords(File(4), Rank(0)));
      final rect = tester.getRect(glow);
      expect(rect.width, 40);
      expect(rect.height, 40);
      expect(rect.center.dx, (800 - 320) / 2 + 4 * 40 + 20);
      expect(rect.center.dy, (600 - 320) / 2 + 7 * 40 + 20);

      // Viewed from Black the file mirrors: x = 3*40.
      await pumpPulse(tester, orientation: Side.black, king: Square.fromCoords(File(4), Rank(0)));
      final flipped = tester.getRect(glow);
      expect(flipped.center.dx, (800 - 320) / 2 + 3 * 40 + 20);
    });

    testWidgets('shows nothing when nobody is in check', (tester) async {
      await pumpPulse(tester, orientation: Side.white, king: null);
      expect(glow, findsNothing);
    });
  });
}
