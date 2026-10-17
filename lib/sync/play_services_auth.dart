import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

import 'google_auth.dart';

/// Android sign-in through Google Play services: the phone's own "Sign in with Google" sheet
/// instead of a browser round trip (Android pauses apps in the background, so the browser's
/// answer to the app's loopback server could hang). Play services keeps the Drive grant; the app
/// only remembers which account was chosen, and asks for a fresh short-lived token for it on each
/// sync. No long-lived Google token is stored on the phone.
///
/// Phones without Play services fall back to the browser flow of [GoogleAuth].
class PlayServicesAuth extends GoogleAuth {
  PlayServicesAuth(super.config, {GoogleSignInPlatform? platform}) : _platform = platform;

  final GoogleSignInPlatform? _platform;
  GoogleSignInPlatform get _api => _platform ?? GoogleSignInPlatform.instance;

  /// Saved credentials of this kind name the account instead of holding a refresh token.
  static const prefix = 'play:';

  static const _scopes = [driveAppDataScope];

  Future<void>? _init;
  String? _access;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _ready() => _init ??= _api.init(InitParameters(serverClientId: config.androidServerClientId));

  @override
  Future<String> signIn(Future<bool> Function(Uri url) openBrowser,
      {Duration timeout = const Duration(minutes: 5)}) async {
    try {
      await _ready();
      final account = await _api.authenticate(const AuthenticateParameters(scopeHint: _scopes));
      final email = account.user.email;
      final token = await _api.clientAuthorizationTokensForScopes(ClientAuthorizationTokensForScopesParameters(
          request: AuthorizationRequestDetails(
              scopes: _scopes, userId: account.user.id, email: email, promptIfUnauthorized: true)));
      if (token == null) {
        throw const AuthException('Chess Coach needs access to its own Google Drive folder. Connect again and '
            'allow it.');
      }
      _keep(token.accessToken);
      return '$prefix$email';
    } on GoogleSignInException catch (e) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled || GoogleSignInExceptionCode.interrupted:
          throw const AuthException('Sign-in was cancelled.');
        case GoogleSignInExceptionCode.clientConfigurationError || GoogleSignInExceptionCode.providerConfigurationError:
          // No Play services on this phone (or not set up for this build): use the browser instead.
          return super.signIn(openBrowser, timeout: timeout);
        default:
          throw AuthException('Google sign-in failed (${e.description ?? e.code.name}).');
      }
    }
  }

  @override
  Future<String> accessToken(String refreshToken) async {
    if (!refreshToken.startsWith(prefix)) return super.accessToken(refreshToken);
    if (_access != null && DateTime.now().isBefore(_expires)) return _access!;
    final email = refreshToken.substring(prefix.length);
    try {
      await _ready();
      final token = await _api.clientAuthorizationTokensForScopes(ClientAuthorizationTokensForScopesParameters(
          request: AuthorizationRequestDetails(
              scopes: _scopes, userId: null, email: email, promptIfUnauthorized: false)));
      if (token == null) throw const AuthException('Google sign-in expired.', signInAgain: true);
      _keep(token.accessToken);
      return token.accessToken;
    } on GoogleSignInException catch (e) {
      throw AuthException('Google sign-in error (${e.description ?? e.code.name}).');
    }
  }

  @override
  Future<void> revoke(String token) async {
    if (!token.startsWith(prefix)) return super.revoke(token);
    try {
      // Revoking an access token removes the app's Drive grant for that account.
      final access = _access ?? await accessToken(token);
      _access = null;
      await super.revoke(access);
      await _ready();
      await _api.disconnect(const DisconnectParams());
    } catch (_) {}
  }

  void _keep(String token) {
    _access = token;
    // Play services tokens last an hour; ask again a little before.
    _expires = DateTime.now().add(const Duration(minutes: 45));
  }
}
