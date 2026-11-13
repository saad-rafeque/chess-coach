import 'dart:io';

import 'package:chess_coach/sync/token_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The binding is what makes the platform channel exist (and have no handler)
  // in this test, so SecureTokenStore sees the same "no keychain here" failure
  // that tests and headless Linux desktops get.
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final next in <String?>['new-account', null]) {
    test(
      'a failed keychain write cannot restore the old account ($next)',
      () async {
        final dir = await Directory.systemTemp.createTemp('keychain-recovery');
        addTearDown(() => dir.delete(recursive: true));
        const channel = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        String? keychain = 'old-account';
        var unavailable = true;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (unavailable) throw PlatformException(code: 'keychain-locked');
          switch (call.method) {
            case 'read':
              return keychain;
            case 'write':
              keychain = (call.arguments as Map)['value'] as String?;
            case 'delete':
              keychain = null;
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final original = SecureTokenStore(directory: () async => dir);
        await original.write(next);
        unavailable = false;
        // Restart after the desktop keychain unlocks: a previous account must
        // never reappear after switching accounts or signing out while locked.
        final restarted = SecureTokenStore(directory: () async => dir);
        expect(await restarted.read(), next);
        expect(keychain, next);
        expect(
          File('${dir.path}/${FileTokenStore.fileName}').existsSync(),
          isFalse,
        );
      },
    );
  }

  test('falls back to the file where no keychain exists', () async {
    final dir = await Directory.systemTemp.createTemp('securetokens');
    addTearDown(() => dir.delete(recursive: true));
    final store = SecureTokenStore(directory: () async => dir);
    expect(await store.read(), isNull);
    await store.write('secret-refresh');
    expect(await store.read(), 'secret-refresh');
    final file = File('${dir.path}/${FileTokenStore.fileName}');
    expect(file.existsSync(), isTrue);
    if (Platform.isLinux || Platform.isMacOS)
      expect(file.statSync().modeString(), 'rw-------');
    await store.write(null);
    expect(await store.read(), isNull);
    expect(
      file.readAsStringSync(),
      isEmpty,
      reason: 'remembers sign-out while the keychain is unavailable',
    );
  });
}
