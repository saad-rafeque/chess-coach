import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chess_coach/sync/google_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = OAuthConfig(
    clientId: 'test-client',
    clientSecret: 'test-secret',
  );

  test('browser access token cache is keyed by refresh credential', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requested = <String>[];
    server.listen((request) async {
      final form = Uri.splitQueryString(
        await utf8.decoder.bind(request).join(),
      );
      final account = form['refresh_token']!;
      requested.add(account);
      request.response.write(jsonEncode({'access_token': 'access-$account'}));
      await request.response.close();
    });
    final auth = GoogleAuth(
      config,
      tokenEndpoint: 'http://127.0.0.1:${server.port}/token',
    );
    expect(await auth.accessToken('a'), 'access-a');
    expect(await auth.accessToken('b'), 'access-b');
    expect(await auth.accessToken('b'), 'access-b');
    expect(requested, ['a', 'b']);
  });

  test('cancelled browser token exchange A cannot replace account B', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final oldRequested = Completer<void>();
    final releaseOld = Completer<void>();
    final requested = <String>[];
    server.listen((request) async {
      final form = Uri.splitQueryString(
        await utf8.decoder.bind(request).join(),
      );
      final account = form['code'] ?? form['refresh_token']!;
      requested.add(account);
      if (account == 'a') {
        oldRequested.complete();
        await releaseOld.future;
      }
      request.response.write(
        jsonEncode({
          'access_token': 'access-$account',
          'refresh_token': account,
          'scope': driveAppDataScope,
        }),
      );
      await request.response.close();
    });
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final redirects = <Future<void>>[];
    Future<bool> redirect(Uri url, String account) async {
      final query = url.queryParameters;
      final callback = Uri.parse(
        query['redirect_uri']!,
      ).replace(queryParameters: {'code': account, 'state': query['state']!});
      redirects.add(
        Future(() async {
          final request = await client.getUrl(callback);
          await (await request.close()).drain<void>();
        }),
      );
      return true;
    }

    final auth = GoogleAuth(
      config,
      tokenEndpoint: 'http://127.0.0.1:${server.port}/token',
    );
    final old = auth.signIn((url) => redirect(url, 'a'));
    final cancelled = expectLater(old, throwsA(isA<AuthException>()));
    await oldRequested.future;
    await auth.cancelSignIn();
    expect(await auth.signIn((url) => redirect(url, 'b')), 'b');
    releaseOld.complete();
    await cancelled;
    await Future.wait(redirects);
    expect(await auth.accessToken('b'), 'access-b');
    expect(requested, ['a', 'b']);
  });
}
