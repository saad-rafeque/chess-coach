import 'package:chess_coach/sync/google_auth.dart';
import 'package:chess_coach/sync/play_services_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

/// Google Play services on a phone, in memory.
class _FakePlay extends GoogleSignInPlatform {
  String? serverClientId;
  bool granted = true;
  GoogleSignInExceptionCode? fail;
  final requests = <AuthorizationRequestDetails>[];

  @override
  Future<void> init(InitParameters params) async => serverClientId = params.serverClientId;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) async {
    if (fail != null) throw GoogleSignInException(code: fail!);
    return const AuthenticationResults(
      user: GoogleSignInUserData(email: 'player@example.com', id: '42'),
      authenticationTokens: AuthenticationTokenData(idToken: 'id'),
    );
  }

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
      ClientAuthorizationTokensForScopesParameters params) async {
    requests.add(params.request);
    return granted ? ClientAuthorizationTokenData(accessToken: 'token${requests.length}') : null;
  }

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(AttemptLightweightAuthenticationParameters params) =>
      null;
  @override
  bool supportsAuthenticate() => true;
  @override
  bool authorizationRequiresUserInteraction() => false;
  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
          ServerAuthorizationTokensForScopesParameters params) async =>
      null;
  @override
  Future<void> signOut(SignOutParams params) async {}
  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

void main() {
  const config = OAuthConfig(clientId: 'desktop', clientSecret: 's', androidServerClientId: 'web-id');

  test('signs in with the phone account and gets tokens without the browser', () async {
    final play = _FakePlay();
    final auth = PlayServicesAuth(config, platform: play);
    final saved = await auth.signIn((_) async => fail('no browser on Android'));
    expect(saved, 'play:player@example.com');
    expect(play.serverClientId, 'web-id');
    expect(play.requests.single.promptIfUnauthorized, isTrue);
    expect(play.requests.single.scopes, [driveAppDataScope]);

    // A later sync on a fresh start asks silently, for that account only.
    final later = PlayServicesAuth(config, platform: play);
    expect(await later.accessToken(saved), 'token2');
    expect(play.requests.last.email, 'player@example.com');
    expect(play.requests.last.promptIfUnauthorized, isFalse);
  });

  test('a removed grant asks to connect again', () async {
    final play = _FakePlay()..granted = false;
    final auth = PlayServicesAuth(config, platform: play);
    await expectLater(auth.accessToken('play:player@example.com'),
        throwsA(isA<AuthException>().having((e) => e.signInAgain, 'signInAgain', isTrue)));
  });

  test('cancelling says so', () async {
    final play = _FakePlay()..fail = GoogleSignInExceptionCode.canceled;
    final auth = PlayServicesAuth(config, platform: play);
    await expectLater(auth.signIn((_) async => true),
        throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('cancelled'))));
  });
}
