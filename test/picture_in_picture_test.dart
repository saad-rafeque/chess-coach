import 'package:chess_coach/app/picture_in_picture.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android PiP action calls native entry point', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('com.saadrafeque.chess_coach/pip');
    var requested = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'enter');
          requested = true;
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    expect(await PictureInPicture.enter(), isTrue);
    expect(requested, isTrue);
  });

  test('non-Android platforms do not call Android PiP', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(PictureInPicture.supported, isFalse);
    expect(await PictureInPicture.enter(), isFalse);
  });

  test('a build without the native PiP handler degrades gracefully', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(await PictureInPicture.enter(), isFalse);
  });
  test('native callbacks update PiP state and deliver hint requests', () async {
    PictureInPicture.initialize();
    final start = PictureInPicture.hints.value;
    final undoStart = PictureInPicture.undoRequests.value;
    final playStart = PictureInPicture.playHintRequests.value;
    Future<void> native(String method, [Object? arguments]) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'com.saadrafeque.chess_coach/pip',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, arguments),
            ),
            (_) {},
          );
    }

    await native('modeChanged', true);
    expect(PictureInPicture.active.value, isTrue);
    await native('hint');
    expect(PictureInPicture.hints.value, start + 1);
    await native('undo');
    expect(PictureInPicture.undoRequests.value, undoStart + 1);
    await native('playHint');
    expect(PictureInPicture.playHintRequests.value, playStart + 1);
    await native('modeChanged', false);
    expect(PictureInPicture.active.value, isFalse);
  });

  test(
    'PiP action availability is sent together to the native window',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('com.saadrafeque.chess_coach/pip');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => calls.add(call),
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await PictureInPicture.setActionsAvailable(
        hint: true,
        undo: true,
        playHint: false,
      );
      expect(calls.single.method, 'actionsAvailable');
      expect(calls.single.arguments, {
        'hint': true,
        'undo': true,
        'playHint': false,
      });
    },
  );

  test(
    'PiP action update retains hints against an older native host',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const channel = MethodChannel('com.saadrafeque.chess_coach/pip');
      var fallback = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'actionsAvailable') throw MissingPluginException();
        fallback = call.method == 'hintAvailable' && call.arguments == true;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await PictureInPicture.setActionsAvailable(
        hint: true,
        undo: false,
        playHint: false,
      );
      expect(fallback, isTrue);
    },
  );
}
