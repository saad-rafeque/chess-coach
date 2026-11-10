import 'dart:async';

import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/sync/drive.dart';
import 'package:chess_coach/sync/google_auth.dart';
import 'package:chess_coach/sync/sync_service.dart';
import 'package:chess_coach/sync/token_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends GoogleAuth {
  _Auth() : super(const OAuthConfig(clientId: 'id', clientSecret: 's'));
  String? failure;
  Completer<String>? signInResult;
  Completer<void>? revokeResult;
  @override
  Future<String> signIn(
    Future<bool> Function(Uri) openBrowser, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (failure != null) throw AuthException(failure!);
    return signInResult?.future ?? Future.value('account');
  }

  @override
  Future<String> accessToken(String refreshToken) async => refreshToken;
  @override
  Future<void> revoke(String token) async {
    await revokeResult?.future;
  }
}

class _Folder implements SyncFolder {
  List<int>? bytes;
  String? fileName;
  int writes = 0;
  Future<void> Function()? beforeRead;
  Future<void> Function()? beforeWrite;
  @override
  Future<RemoteFile?> find(String name) async =>
      bytes == null ? null : const RemoteFile('file', null);
  @override
  Future<List<RemoteFile>> findAll(String name) async =>
      bytes != null && fileName == name ? [const RemoteFile('file', null)] : [];

  @override
  Future<List<int>> read(String id) async {
    await beforeRead?.call();
    return bytes!;
  }

  @override
  Future<String> create(String name, List<int> data) async {
    fileName = name;
    await write('file', data);
    return 'file';
  }

  @override
  Future<void> write(String id, List<int> data) async {
    await beforeWrite?.call();
    bytes = data;
    writes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Folder folder;
  late _Auth auth;
  late EventStore store;
  late AppSettings settings;
  late MemoryTokenStore tokens;
  late SyncService service;
  setUp(() {
    folder = _Folder();
    auth = _Auth();
    store = EventStore.memory();
    settings = AppSettings.memory();
    tokens = MemoryTokenStore();
    service = SyncService(
      store: store,
      settings: settings,
      config: auth.config,
      auth: auth,
      tokens: tokens,
      folder: (_) => folder,
      retryDelays: const [],
    );
  });
  tearDown(() => service.dispose());

  test('background sync uploads settings-only changes', () async {
    await service.connect();
    final writes = folder.writes;
    settings.theme = AppTheme.wooden;
    service.didChangeAppLifecycleState(AppLifecycleState.paused);
    await service.sync();
    expect(folder.writes, writes + 1);
    expect(SyncPayload.decode(folder.bytes!).settings!['theme'], 'wooden');
  });

  test('changes made during an upload are sent in a follow-up pass', () async {
    await service.connect();
    await store.add('puzzle', {'id': 'first'});
    final started = Completer<void>(), release = Completer<void>();
    folder.beforeWrite = () async {
      folder.beforeWrite = null;
      started.complete();
      await release.future;
    };
    final syncing = service.sync();
    await started.future;
    await store.add('puzzle', {'id': 'second'});
    settings.theme = AppTheme.light;
    release.complete();
    expect(await syncing, isTrue);
    final uploaded = SyncPayload.decode(folder.bytes!);
    expect(
      uploaded.events.map((e) => e.data['id']),
      containsAll(['first', 'second']),
    );
    expect(uploaded.settings!['theme'], 'light');
    expect(service.status, SyncStatus.idle);
  });

  test(
    'disconnect invalidates a pending read before merging or saving account metadata',
    () async {
      await service.connect();
      folder.bytes = SyncPayload(
        events: [
          AppEvent(
            id: 'remote',
            type: 'puzzle',
            time: DateTime.now(),
            device: 'other',
            data: const {'id': 'remote'},
          ),
        ],
      ).encode();
      final started = Completer<void>(), release = Completer<void>();
      folder.beforeRead = () async {
        started.complete();
        await release.future;
      };
      final syncing = service.sync();
      await started.future;
      await service.disconnect();
      release.complete();
      expect(await syncing, isFalse);
      expect(store.events, isEmpty);
      expect(settings.readValue('syncSnapshotFileId'), isNull);
      expect(settings.readValue('syncLast'), isNull);
      expect(tokens.token, isNull);
      expect(service.status, SyncStatus.signedOut);
    },
  );

  test('failed sign-in exposes its error while disconnected', () async {
    auth.failure = 'Drive access was not granted';
    await service.connect();
    expect(service.connected, isFalse);
    expect(service.status, SyncStatus.error);
    expect(service.error, contains('Drive access'));
  });

  test('cancelled sign-in ignores a delayed authentication result', () async {
    auth.signInResult = Completer<String>();
    final connecting = service.connect();
    await Future<void>.delayed(Duration.zero);
    await service.cancelSignIn();
    auth.signInResult!.complete('late-account');
    await connecting;
    expect(service.connected, isFalse);
    expect(tokens.token, isNull);
    expect(folder.writes, 0);
  });

  test(
    'another account cannot connect while old authorization is being revoked',
    () async {
      await service.connect();
      auth.revokeResult = Completer<void>();
      final disconnecting = service.disconnect();
      await Future<void>.delayed(Duration.zero);
      expect(service.status, SyncStatus.disconnecting);
      await service.connect();
      expect(service.connected, isFalse);
      auth.revokeResult!.complete();
      await disconnecting;
      expect(service.status, SyncStatus.signedOut);
    },
  );

  test('disposing during an upload prevents late metadata writes', () async {
    await service.connect();
    await store.add('puzzle', {'id': 'pending'});
    final oldLast = settings.readValue('syncLast');
    final started = Completer<void>(), release = Completer<void>();
    folder.beforeWrite = () async {
      started.complete();
      await release.future;
    };
    final syncing = service.sync();
    await started.future;
    service.dispose();
    release.complete();
    expect(await syncing, isFalse);
    expect(settings.readValue('syncLast'), oldLast);
    // Avoid disposing the same notifier a second time in tearDown.
    service = SyncService(
      store: store,
      settings: settings,
      config: auth.config,
    );
  });
}
