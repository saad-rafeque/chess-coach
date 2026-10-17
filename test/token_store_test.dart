import 'dart:io';

import 'package:chess_coach/sync/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The binding is what makes the platform channel exist (and have no handler)
  // in this test, so SecureTokenStore sees the same "no keychain here" failure
  // that tests and headless Linux desktops get.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('falls back to the file where no keychain exists', () async {
    final dir = await Directory.systemTemp.createTemp('securetokens');
    addTearDown(() => dir.delete(recursive: true));
    final store = SecureTokenStore(directory: () async => dir);
    expect(await store.read(), isNull);
    await store.write('secret-refresh');
    expect(await store.read(), 'secret-refresh');
    final file = File('${dir.path}/${FileTokenStore.fileName}');
    expect(file.existsSync(), isTrue);
    if (Platform.isLinux || Platform.isMacOS) expect(file.statSync().modeString(), 'rw-------');
    await store.write(null);
    expect(file.existsSync(), isFalse);
  });
}
