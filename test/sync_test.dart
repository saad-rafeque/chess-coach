import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/sync/drive.dart';
import 'package:chess_coach/sync/google_auth.dart';
import 'package:chess_coach/sync/sync_service.dart';
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
      retryDelays: const [Duration(milliseconds: 10)],
    );

void main() {
  group('sync', () {
    test('two devices end up with the union of their events and the newest settings', () async {
      final folder = _MemoryFolder();
      final phoneStore = EventStore.memory(device: 'phone'), pcStore = EventStore.memory(device: 'pc');
      final phoneSettings = AppSettings.memory(), pcSettings = AppSettings.memory();
      final phone = _device(phoneStore, phoneSettings, folder), pc = _device(pcStore, pcSettings, folder);

      await phoneStore.add('puzzle', {'id': 'a'});
      await pcStore.add('puzzle', {'id': 'b'});
      await pcStore.add('game', {'id': 'c'});

      await phone.connect();
      expect(phone.status, SyncStatus.idle);
      expect(folder.files, hasLength(1));

      await Future<void>.delayed(const Duration(milliseconds: 5));
      pcSettings.theme = AppTheme.wooden; // changed later than the phone's defaults
      await pc.connect();
      expect(pcStore.events.map((e) => e.data['id']), containsAll(['a', 'b', 'c']));

      await phone.sync();
      expect(phoneStore.events.map((e) => e.data['id']).toSet(), {'a', 'b', 'c'});
      expect(phoneSettings.theme, AppTheme.wooden);

      // Nothing new: no upload.
      final writes = folder.writes;
      await phone.sync();
      expect(folder.writes, writes);
    });

    test('older remote settings do not overwrite newer local ones', () async {
      final folder = _MemoryFolder();
      final a = AppSettings.memory()..theme = AppTheme.light;
      final devA = _device(EventStore.memory(), a, folder);
      await devA.connect();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = AppSettings.memory()..theme = AppTheme.wooden;
      final devB = _device(EventStore.memory(), b, folder);
      await devB.connect();
      expect(b.theme, AppTheme.wooden);
      await devA.sync();
      expect(a.theme, AppTheme.wooden);
    });

    test('offline: keeps local data and retries when the network returns', () async {
      final folder = _MemoryFolder()..offline = true;
      final store = EventStore.memory();
      await store.add('puzzle', {'id': 'x'});
      final s = _device(store, AppSettings.memory(), folder);
      await s.connect();
      expect(s.status, SyncStatus.offline);
      folder.offline = false;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(s.status, SyncStatus.idle);
      expect(folder.files, hasLength(1));
    });

    test('a revoked sign-in asks to connect again', () async {
      final auth = _FakeAuth();
      final s = _device(EventStore.memory(), AppSettings.memory(), _MemoryFolder(), auth: auth);
      await s.connect();
      auth.expired = true;
      expect(await s.sync(), isFalse);
      expect(s.connected, isFalse);
      expect(s.error, contains('Connect again'));
    });

    test('without a configured OAuth client sync stays off', () async {
      final s = SyncService(store: EventStore.memory(), settings: AppSettings.memory(), config: const OAuthConfig(clientId: '', clientSecret: ''));
      expect(s.status, SyncStatus.notSetUp);
      expect(await s.sync(), isFalse);
    });

    test('payload round trip', () {
      final e = AppEvent(id: '1', type: 'puzzle', time: DateTime.utc(2026), device: 'd', data: const {'solved': true});
      final p = SyncPayload.decode(
          SyncPayload(events: [e], settings: const {'theme': 'dark'}, settingsChanged: DateTime.utc(2026, 2)).encode());
      expect(p.events.single.toJson(), e.toJson());
      expect(p.settings, {'theme': 'dark'});
      expect(p.settingsChanged, DateTime.utc(2026, 2));
    });
  });

  group('Google sign-in', () {
    test('PKCE challenge matches RFC 7636', () {
      expect(codeChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
      expect(newCodeVerifier(), matches(RegExp(r'^[A-Za-z0-9\-._~]{64}$')));
    });

    test('loopback sign-in exchanges the code and refreshes tokens', () async {
      final token = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final forms = <Map<String, String>>[];
      token.listen((req) async {
        final form = Uri.splitQueryString(await utf8.decoder.bind(req).join());
        forms.add(form);
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'access_token': 'acc${forms.length}',
          'expires_in': form['grant_type'] == 'refresh_token' ? 3600 : 30,
          if (form['grant_type'] == 'authorization_code') 'refresh_token': 'ref',
        }));
        await req.response.close();
      });
      final auth = GoogleAuth(const OAuthConfig(clientId: 'cid', clientSecret: 'sec'),
          tokenEndpoint: 'http://127.0.0.1:${token.port}/token');
      final refresh = await auth.signIn((url) async {
        final q = url.queryParameters;
        expect(q['scope'], driveAppDataScope);
        expect(q['code_challenge_method'], 'S256');
        // Play the browser: Google redirects back to the loopback server.
        unawaited(HttpClient()
            .getUrl(Uri.parse('${q['redirect_uri']}/?code=abc&state=${q['state']}'))
            .then((r) => r.close()));
        return true;
      });
      expect(refresh, 'ref');
      expect(forms.first['code'], 'abc');
      expect(forms.first['code_verifier'], hasLength(64));
      // The first token expires within the safety margin, so it is refreshed.
      expect(await auth.accessToken('ref'), 'acc2');
      expect(forms.last['grant_type'], 'refresh_token');
      expect(await auth.accessToken('ref'), 'acc2', reason: 'cached until it expires');
      await token.close(force: true);
    });
  });
}
