import 'dart:async';

import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/sync/drive.dart';
import 'package:chess_coach/sync/google_auth.dart';
import 'package:chess_coach/sync/sync_service.dart';
import 'package:chess_coach/sync/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends GoogleAuth {
  _Auth() : super(const OAuthConfig(clientId: 'id', clientSecret: 'secret'));
  @override
  Future<String> signIn(
    Future<bool> Function(Uri) browser, {
    Duration timeout = const Duration(minutes: 5),
  }) async => 'account';
  @override
  Future<String> accessToken(String token) async => token;
  @override
  Future<void> revoke(String token) async {}
}

class _Cloud {
  final files = <String, ({String name, String owner, List<int> bytes})>{};
  final writes = <String>[];
  Completer<void>? firstListingBarrier;
  int firstListings = 0;
  int nextId = 0;
}

class _Folder implements SyncFolder {
  _Folder(this.cloud, this.owner);
  final _Cloud cloud;
  final String owner;
  @override
  Future<RemoteFile?> find(String name) async =>
      (await findAll(name)).firstOrNull;
  @override
  Future<List<RemoteFile>> findAll(String name) async {
    final result = [
      for (final e in cloud.files.entries)
        if (e.value.name == name) RemoteFile(e.key, null),
    ];
    final barrier = cloud.firstListingBarrier;
    if (barrier != null &&
        name == SyncPayload.snapshotFileName &&
        result.isEmpty) {
      if (++cloud.firstListings == 2) {
        cloud.firstListingBarrier = null;
        barrier.complete();
      }
      await barrier.future;
    }
    return result;
  }

  @override
  Future<List<int>> read(String id) async {
    if (!cloud.files.containsKey(id))
      throw const DriveException(404, 'missing');
    return cloud.files[id]!.bytes;
  }

  @override
  Future<String> create(String name, List<int> bytes) async {
    final id = 'file${++cloud.nextId}';
    cloud.files[id] = (name: name, owner: owner, bytes: bytes);
    return id;
  }

  @override
  Future<void> write(String id, List<int> bytes) async {
    final previous = cloud.files[id]!;
    if (previous.owner != owner)
      throw StateError('Attempt to overwrite peer snapshot');
    cloud.writes.add(id);
    cloud.files[id] = (name: previous.name, owner: owner, bytes: bytes);
  }
}

SyncService _device(
  _Cloud cloud,
  String name,
  EventStore store,
  AppSettings settings,
) => SyncService(
  store: store,
  settings: settings,
  config: const OAuthConfig(clientId: 'id', clientSecret: 'secret'),
  auth: _Auth(),
  tokens: MemoryTokenStore(),
  folder: (_) => _Folder(cloud, name),
  retryDelays: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'simultaneous first syncs discover each other without sharing a writable file',
    () async {
      final cloud = _Cloud()..firstListingBarrier = Completer<void>();
      final aStore = EventStore.memory(), bStore = EventStore.memory();
      await aStore.add('puzzle', {'id': 'a'});
      await bStore.add('puzzle', {'id': 'b'});
      final a = _device(cloud, 'a', aStore, AppSettings.memory());
      final b = _device(cloud, 'b', bStore, AppSettings.memory());
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await Future.wait([a.connect(), b.connect()]);
      await Future.wait([a.sync(), b.sync()]);
      expect(cloud.files.length, 2);
      expect(aStore.events.map((e) => e.data['id']), containsAll(['a', 'b']));
      expect(bStore.events.map((e) => e.data['id']), containsAll(['a', 'b']));
      expect(a.status, SyncStatus.idle);
      expect(b.status, SyncStatus.idle);

      await aStore.add('puzzle', {'id': 'a2'});
      await bStore.add('puzzle', {'id': 'b2'});
      expect(await Future.wait([a.sync(), b.sync()]), everyElement(isTrue));
      final cStore = EventStore.memory();
      final c = _device(cloud, 'c', cStore, AppSettings.memory());
      addTearDown(c.dispose);
      await c.connect();
      expect(
        cStore.events.map((e) => e.data['id']),
        containsAll(['a', 'b', 'a2', 'b2']),
      );
    },
  );

  test(
    'all duplicate legacy files are imported and remain untouched',
    () async {
      final cloud = _Cloud();
      for (final id in ['legacy1', 'legacy2']) {
        final event = AppEvent(
          id: id,
          type: 'puzzle',
          time: DateTime.now(),
          device: 'old',
          data: {'id': id},
        );
        cloud.files[id] = (
          name: SyncPayload.fileName,
          owner: 'legacy',
          bytes: SyncPayload(events: [event]).encode(),
        );
      }
      final original = Map.of(cloud.files);
      final store = EventStore.memory();
      final device = _device(cloud, 'new', store, AppSettings.memory());
      addTearDown(device.dispose);
      await device.connect();
      expect(
        store.events.map((e) => e.data['id']),
        containsAll(['legacy1', 'legacy2']),
      );
      for (final id in original.keys)
        expect(cloud.files[id]!.bytes, original[id]!.bytes);
      expect(cloud.files.length, 3);
      expect(cloud.writes.where((id) => id.startsWith('legacy')), isEmpty);
    },
  );

  test(
    'reconnecting the same installation reuses its owned snapshot',
    () async {
      final cloud = _Cloud();
      final settings = AppSettings.memory();
      final device = _device(cloud, 'phone', EventStore.memory(), settings);
      addTearDown(device.dispose);
      await device.connect();
      final snapshot = settings.readValue('syncSnapshotFileId');
      await device.disconnect();
      await device.connect();
      expect(cloud.files.length, 1);
      expect(settings.readValue('syncSnapshotFileId'), snapshot);
    },
  );

}
