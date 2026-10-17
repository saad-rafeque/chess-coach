import 'dart:io';

import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/main.dart';
import 'package:chess_coach/sync/drive.dart';
import 'package:chess_coach/sync/google_auth.dart';
import 'package:chess_coach/sync/sync_service.dart';
import 'package:chess_coach/sync/token_store.dart';
import 'package:fluent_ui/fluent_ui.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

/// Drive app folder in memory, shared by several "devices".
class _MemoryFolder implements SyncFolder {
  final files = <String, (String, List<int>)>{};
  int writes = 0;
  bool offline = false;
  Future<String> Function()? token;

  Future<void> _check() async {
    if (offline) throw const SocketException('offline');
    await token?.call();
  }

  @override
  Future<RemoteFile?> find(String name) async {
    await _check();
    for (final MapEntry(key: id, value: (n, _)) in files.entries) {
      if (n == name) return RemoteFile(id, null);
    }
    return null;
  }

  @override
  Future<List<int>> read(String id) async {
    await _check();
    final f = files[id];
    if (f == null) throw const DriveException(404, 'gone');
    return f.$2;
  }

  @override
  Future<String> create(String name, List<int> bytes) async {
    await _check();
    writes++;
    final id = 'f${files.length + 1}';
    files[id] = (name, bytes);
    return id;
  }

  @override
  Future<void> write(String id, List<int> bytes) async {
    await _check();
    writes++;
    files[id] = (files[id]!.$1, bytes);
  }
}

/// Auth that never talks to Google.
class _FakeAuth extends GoogleAuth {
  _FakeAuth() : super(const OAuthConfig(clientId: 'id', clientSecret: 's'));

  bool expired = false;

  @override
  Future<String> signIn(Future<bool> Function(Uri url) openBrowser, {Duration timeout = const Duration(minutes: 5)}) async =>
      'refresh-token';

  @override
  Future<String> accessToken(String refreshToken) async {
    if (expired) throw const AuthException('invalid_grant', signInAgain: true);
    return 'access';
  }

  @override
  Future<void> revoke(String token) async {}
}

SyncService _device(EventStore store, AppSettings settings, _MemoryFolder folder, {_FakeAuth? auth}) => SyncService(
      store: store,
      settings: settings,
      config: const OAuthConfig(clientId: 'id', clientSecret: 's'),
      auth: auth ?? _FakeAuth(),
      folder: (token) => folder..token = token,
      openBrowser: (_) async => true,
      tokens: MemoryTokenStore(),
      retryDelays: const [Duration(milliseconds: 10)],
    );

void main() {
  testWidgets('Home has a sync button once connected', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final folder = _MemoryFolder();
    final store = EventStore.memory(), settings = AppSettings.memory();
    final sync = _device(store, settings, folder);
    await tester.runAsync(sync.connect);
    await tester.pumpWidget(ChessCoachApp(settings: settings, store: store, sync: sync));
    await tester.pumpAndSettle();
    expect(find.text('Synced just now'), findsOneWidget);
    final writes = folder.writes;
    await store.add('puzzle', {'id': 'new'});
    await tester.tap(find.text('Synced just now'));
    await tester.pumpAndSettle();
    expect(folder.writes, writes + 1);
  });
}
