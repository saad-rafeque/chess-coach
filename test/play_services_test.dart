import 'dart:async';
import 'dart:io';

import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/sync/google_auth.dart';
import 'package:chess_coach/sync/play_services_auth.dart';
import 'package:chess_coach/sync/sync_service.dart';
import 'package:chess_coach/sync/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

/// Google Play services on a phone, in memory.
class _FakePlay extends GoogleSignInPlatform {
  String? serverClientId;
  bool granted = true;
  GoogleSignInExceptionCode? fail;
  String email = 'player@example.com';
  Future<ClientAuthorizationTokenData?> Function(AuthorizationRequestDetails)?
  authorization;
  final requests = <AuthorizationRequestDetails>[];
  final cleared = <String>[];

  @override
  Future<void> clearAuthorizationToken(
    ClearAuthorizationTokenParams params,
  ) async {
    cleared.add(params.accessToken);
  }

  @override
  Future<void> init(InitParameters params) async =>
      serverClientId = params.serverClientId;

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    if (fail != null) throw GoogleSignInException(code: fail!);
    return AuthenticationResults(
      user: GoogleSignInUserData(email: email, id: email),
      authenticationTokens: const AuthenticationTokenData(idToken: 'id'),
    );
  }

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async {
    requests.add(params.request);
    if (authorization != null) return authorization!(params.request);
    return granted
        ? ClientAuthorizationTokenData(accessToken: 'token${requests.length}')
        : null;
  }

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) => null;
  @override
  bool supportsAuthenticate() => true;
  @override
  bool authorizationRequiresUserInteraction() => false;
  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => null;
  @override
  Future<void> signOut(SignOutParams params) async {}
  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const config = OAuthConfig(
    clientId: 'desktop',
    clientSecret: 's',
    androidServerClientId: 'web-id',
  );

  test(
    'signs in with the phone account and gets tokens without the browser',
    () async {
      final play = _FakePlay();
      final auth = PlayServicesAuth(config, platform: play);
      final saved = await auth.signIn(
        (_) async => fail('no browser on Android'),
      );
      expect(saved, 'play:player@example.com');
      expect(play.serverClientId, 'web-id');
      expect(play.requests.single.promptIfUnauthorized, isTrue);
      expect(play.requests.single.scopes, [driveAppDataScope]);

      // A later sync on a fresh start asks silently, for that account only.
      final later = PlayServicesAuth(config, platform: play);
      expect(await later.accessToken(saved), 'token2');
      expect(play.requests.last.email, 'player@example.com');
      expect(play.requests.last.promptIfUnauthorized, isFalse);
    },
  );

  test('a removed grant asks to connect again', () async {
    final play = _FakePlay()..granted = false;
    final auth = PlayServicesAuth(config, platform: play);
    await expectLater(
      auth.accessToken('play:player@example.com'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.signInAgain,
          'signInAgain',
          isTrue,
        ),
      ),
    );
  });

  test(
    'rejected native token is evicted from both caches for its account',
    () async {
      final play = _FakePlay();
      final auth = PlayServicesAuth(config, platform: play);
      expect(await auth.accessToken('play:a@example.com'), 'token1');
      await auth.invalidateAccessToken('play:b@example.com');
      expect(await auth.accessToken('play:a@example.com'), 'token1');
      expect(play.cleared, isEmpty);
      await auth.invalidateAccessToken('play:a@example.com');
      expect(play.cleared, ['token1']);
      expect(await auth.accessToken('play:a@example.com'), 'token2');
      expect(play.requests.last.email, 'a@example.com');
    },
  );

  test(
    'native cached access tokens are reused only for their account',
    () async {
      final play = _FakePlay();
      final auth = PlayServicesAuth(config, platform: play);
      expect(await auth.accessToken('play:a@example.com'), 'token1');
      expect(await auth.accessToken('play:b@example.com'), 'token2');
      expect(await auth.accessToken('play:b@example.com'), 'token2');
      expect(play.requests.map((r) => r.email), [
        'a@example.com',
        'b@example.com',
      ]);
    },
  );

  test(
    'cancelled native sign-in A cannot replace the later account B token',
    () async {
      final oldToken = Completer<ClientAuthorizationTokenData?>();
      final oldRequested = Completer<void>();
      final play = _FakePlay()..email = 'a@example.com';
      play.authorization = (request) async {
        if (request.email == 'a@example.com') {
          oldRequested.complete();
          return oldToken.future;
        }
        return const ClientAuthorizationTokenData(accessToken: 'access-b');
      };
      final auth = PlayServicesAuth(config, platform: play);
      final old = auth.signIn((_) async => true);
      final cancelled = expectLater(old, throwsA(isA<AuthException>()));
      await oldRequested.future;
      await auth.cancelSignIn();
      play.email = 'b@example.com';
      expect(await auth.signIn((_) async => true), 'play:b@example.com');
      oldToken.complete(
        const ClientAuthorizationTokenData(accessToken: 'access-a'),
      );
      await cancelled;
      expect(await auth.accessToken('play:b@example.com'), 'access-b');
      expect(play.requests, hasLength(2));
    },
  );

  test('cancelling says so', () async {
    final play = _FakePlay()..fail = GoogleSignInExceptionCode.canceled;
    final auth = PlayServicesAuth(config, platform: play);
    await expectLater(
      auth.signIn((_) async => true),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('cancelled'),
        ),
      ),
    );
  });

  test('Android-only sign-in configuration enables Connect and sync', () async {
    const androidOnly = OAuthConfig(
      clientId: '',
      clientSecret: '',
      androidServerClientId: 'web-id',
    );
    final auth = PlayServicesAuth(androidOnly, platform: _FakePlay());
    final sync = SyncService(
      store: EventStore.memory(),
      settings: AppSettings.memory(),
      config: androidOnly,
      auth: auth,
      tokens: MemoryTokenStore(),
      folder: (_) => throw const SocketException('test offline'),
      retryDelays: const [],
    );
    addTearDown(sync.dispose);
    expect(sync.status, SyncStatus.signedOut);
    await sync.connect();
    expect(sync.connected, isTrue);
    expect(sync.status, SyncStatus.offline);
  });

  test(
    'Android-only config does not enable an unconfigured desktop browser',
    () {
      final sync = SyncService(
        store: EventStore.memory(),
        settings: AppSettings.memory(),
        config: const OAuthConfig(
          clientId: '',
          clientSecret: '',
          androidServerClientId: 'web-id',
        ),
        auth: GoogleAuth(const OAuthConfig(clientId: '', clientSecret: '')),
      );
      addTearDown(sync.dispose);
      expect(sync.status, SyncStatus.notSetUp);
    },
  );

  test(
    'Android config failure does not launch an empty browser OAuth client',
    () async {
      final play = _FakePlay()
        ..fail = GoogleSignInExceptionCode.clientConfigurationError;
      final auth = PlayServicesAuth(
        const OAuthConfig(
          clientId: '',
          clientSecret: '',
          androidServerClientId: 'web-id',
        ),
        platform: play,
      );
      await expectLater(
        auth.signIn((_) async => fail('unconfigured browser must not launch')),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('unavailable'),
          ),
        ),
      );
    },
  );
}
