import 'dart:convert';
import 'dart:io';

import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/sync/drive.dart';
import 'package:chess_coach/sync/google_auth.dart';
import 'package:chess_coach/sync/sync_service.dart';
import 'package:chess_coach/sync/token_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final originalHttp = HttpOverrides.current;
  TestWidgetsFlutterBinding.ensureInitialized();
  // These are real loopback HTTP protocol tests, not widget network mocks.
  HttpOverrides.global = originalHttp;

  for (final (revoked, startOffline) in [
    (false, false),
    (true, false),
    (true, true),
  ]) {
    test(
      'Drive 401 refreshes once, revoked=$revoked, offline=$startOffline',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var exchanges = 0;
        final received = <String>[];
        final files = <String, List<int>>{};
        server.listen((request) async {
          await request.drain<void>();
          if (request.uri.path == '/token') {
            request.response.write(
              jsonEncode({'access_token': 'access-${++exchanges}'}),
            );
          } else {
            final token = request.headers.value(
              HttpHeaders.authorizationHeader,
            )!;
            received.add(token);
            if (token == 'Bearer access-1' || revoked) {
              request.response.statusCode = HttpStatus.unauthorized;
              request.response.write('{"error":"invalid_token"}');
            } else if (request.method == 'POST') {
              // Keep creation response valid; listing remains empty to avoid
              // coupling auth recovery to the snapshot encoding format.
              request.response.write('{"id":"snapshot"}');
            } else if (request.uri.path.endsWith('/snapshot')) {
              request.response.statusCode = HttpStatus.notFound;
            } else {
              request.response.write(
                jsonEncode({
                  'files': files.keys.map((id) => {'id': id}).toList(),
                }),
              );
            }
          }
          await request.response.close();
        });
        final base = 'http://127.0.0.1:${server.port}';
        const config = OAuthConfig(clientId: 'id', clientSecret: 's');
        final auth = GoogleAuth(config, tokenEndpoint: '$base/token');
        final credentials = MemoryTokenStore()..token = 'refresh';
        var offline = startOffline;
        final service = SyncService(
          store: EventStore.memory(),
          settings: AppSettings.memory(),
          config: config,
          auth: auth,
          tokens: credentials,
          folder: (token) {
            if (offline) throw const SocketException('offline');
            return DriveAppFolder(token, base: base);
          },
          retryDelays: const [],
        );
        addTearDown(service.dispose);
        if (startOffline) {
          expect(await service.sync(), isFalse);
          expect(service.status, SyncStatus.offline);
          offline = false;
        }
        expect(await service.sync(), !revoked);
        expect(
          exchanges,
          2,
          reason: 'one fresh token retry, never an auth loop',
        );
        expect(received.first, 'Bearer access-1');
        expect(received.skip(1), everyElement('Bearer access-2'));
        expect(service.connected, !revoked);
        if (revoked) {
          expect(service.status, SyncStatus.error);
          expect(credentials.token, isNull);
          expect(service.error, contains('Connect again'));
        } else {
          expect(service.status, SyncStatus.idle);
        }
      },
    );
  }
}
