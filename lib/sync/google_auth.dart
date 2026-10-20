import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// The Google OAuth client ("Desktop app" type) the owner creates once; passed to builds
/// with `--dart-define` (see docs/google-drive-sync.md). Empty = sync not set up.
class OAuthConfig {
  const OAuthConfig({required this.clientId, required this.clientSecret, this.androidServerClientId = ''});

  static const fromEnvironment = OAuthConfig(
    clientId: String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID'),
    clientSecret: String.fromEnvironment('GOOGLE_OAUTH_CLIENT_SECRET'),
    androidServerClientId: String.fromEnvironment('GOOGLE_ANDROID_SERVER_CLIENT_ID'),
  );

  final String clientId;

  /// Google issues one for installed apps too; it is not treated as a secret there.
  final String clientSecret;

  /// The "Web application" client id that Android's Google sign-in needs (see PlayServicesAuth).
  /// Empty: Android uses the browser flow like the desktop.
  final String androidServerClientId;

  bool get isSet => clientId.isNotEmpty;
}

/// Only the app's own hidden folder in the user's Drive.
const driveAppDataScope = 'https://www.googleapis.com/auth/drive.appdata';

class AuthException implements Exception {
  const AuthException(this.message, {this.signInAgain = false});

  final String message;

  /// The saved sign-in no longer works (revoked or expired).
  final bool signInAgain;

  @override
  String toString() => message;
}

/// PKCE code verifier: 64 random URL-safe characters.
String newCodeVerifier([math.Random? random]) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final r = random ?? math.Random.secure();
  return List.generate(64, (_) => chars[r.nextInt(chars.length)]).join();
}

/// PKCE S256 challenge for [verifier].
String codeChallenge(String verifier) =>
    base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

/// Google sign-in for installed apps: the system browser signs in and Google redirects
/// to a one-shot server on 127.0.0.1 (loopback flow with PKCE). Works the same on
/// Android, Windows and Linux, with no extra SDK.
class GoogleAuth {
  GoogleAuth(
    this.config, {
    HttpClient Function()? client,
    this.authEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth',
    this.tokenEndpoint = 'https://oauth2.googleapis.com/token',
    this.revokeEndpoint = 'https://oauth2.googleapis.com/revoke',
  }) : _client = client ?? HttpClient.new;

  final OAuthConfig config;
  final HttpClient Function() _client;
  final String authEndpoint;
  final String tokenEndpoint;
  final String revokeEndpoint;

  String? _access;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  HttpServer? _server;

  /// Opens Google sign-in with [openBrowser] and waits for the answer.
  /// Returns the refresh token to store.
  Future<String> signIn(Future<bool> Function(Uri url) openBrowser,
      {Duration timeout = const Duration(minutes: 5)}) async {
    await cancelSignIn();
    final server = _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirect = 'http://127.0.0.1:${server.port}';
      final verifier = newCodeVerifier();
      final state = newCodeVerifier().substring(0, 24);
      final url = Uri.parse(authEndpoint).replace(queryParameters: {
        'client_id': config.clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': driveAppDataScope,
        'code_challenge': codeChallenge(verifier),
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
      });
      if (!await openBrowser(url)) throw const AuthException('Could not open the browser.');
      String? code;
      await for (final req in server.timeout(timeout)) {
        final q = req.uri.queryParameters;
        _secureHeaders(req.response);
        // Only Google's redirect for this sign-in counts (it carries our random state). Anything
        // else, such as a favicon request or another program or web page poking the port, is
        // turned away and we keep waiting, so it can neither slip in its own code nor cancel.
        if (req.method != 'GET' || req.uri.path != '/' || q['state'] != state ||
            !(q.containsKey('code') || q.containsKey('error'))) {
          req.response.statusCode = HttpStatus.badRequest;
          await req.response.close();
          continue;
        }
        final ok = (q['code'] ?? '').isNotEmpty;
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write('<!doctype html><html><body style="font-family:sans-serif;text-align:center;padding-top:60px">'
              '<h2>${ok ? 'Signed in' : 'Sign-in cancelled'}</h2>'
              '<p>You can close this tab and go back to Chess Coach.</p></body></html>');
        await req.response.close();
        if (!ok) throw AuthException(q['error'] == 'access_denied' ? 'Sign-in was cancelled.' : 'Sign-in failed.');
        code = q['code'];
        break;
      }
      if (code == null) throw const AuthException('Sign-in was cancelled.');
      final tokens = await _post(tokenEndpoint, {
        'code': code,
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      });
      _remember(tokens);
      // Google lets people untick the Drive box on the consent page; sync can't work without it.
      final scope = tokens['scope'];
      if (scope is String && !scope.split(' ').contains(driveAppDataScope)) {
        throw const AuthException('Chess Coach needs access to its own Google Drive folder. Connect again and '
            'tick the box for it.');
      }
      final refresh = tokens['refresh_token'];
      if (refresh is! String || refresh.isEmpty) {
        throw const AuthException('Google did not allow offline access. Try again.');
      }
      return refresh;
    } on TimeoutException {
      throw const AuthException('Sign-in took too long. Try again.');
    } finally {
      await server.close(force: true);
      if (identical(_server, server)) _server = null;
    }
  }

  /// Stops waiting for a sign-in started with [signIn].
  Future<void> cancelSignIn() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// A valid access token, refreshed with [refreshToken] when needed.
  Future<String> accessToken(String refreshToken) async {
    if (_access != null && DateTime.now().isBefore(_expires)) return _access!;
    final tokens = await _post(tokenEndpoint, {
      'refresh_token': refreshToken,
      'client_id': config.clientId,
      'client_secret': config.clientSecret,
      'grant_type': 'refresh_token',
    });
    _remember(tokens);
    return _access!;
  }

  /// Signs out on Google's side too (best effort).
  Future<void> revoke(String token) async {
    _access = null;
    try {
      await _post(revokeEndpoint, {'token': token});
    } catch (_) {}
  }

  void _remember(Map<String, dynamic> tokens) {
    final access = tokens['access_token'];
    if (access is! String || access.isEmpty) throw const AuthException('Google sent no access token.');
    _access = access;
    final seconds = (tokens['expires_in'] is num ? (tokens['expires_in'] as num).toInt() : 3600).clamp(60, 86400);
    _expires = DateTime.now().add(Duration(seconds: seconds - 60));
  }

  Future<Map<String, dynamic>> _post(String url, Map<String, String> form) async {
    final client = _client()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(Uri.parse(url));
      req.followRedirects = false;
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(Uri(queryParameters: form).query);
      final res = await req.close().timeout(const Duration(seconds: 60));
      if (res.isRedirect || (res.statusCode >= 300 && res.statusCode < 400)) {
        throw const HttpException('The authentication endpoint unexpectedly redirected.');
      }
      final text = utf8.decode(await _readSmall(res), allowMalformed: true);
      Object? json;
      try {
        json = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      } on FormatException {
        json = null;
      }
      // Not JSON: a captive portal or proxy answered instead of Google. Treat it as no network.
      if (json is! Map<String, dynamic>) throw const HttpException('Unexpected answer from the network.');
      if (res.statusCode != HttpStatus.ok) {
        final error = json['error'] is String ? json['error'] as String : 'http ${res.statusCode}';
        throw AuthException('Google sign-in error: $error', signInAgain: error == 'invalid_grant');
      }
      return json;
    } finally {
      client.close();
    }
  }

  /// Token answers are tiny; refuse anything big or stalled.
  static Future<List<int>> _readSmall(Stream<List<int>> response) async {
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 60))) {
      bytes.addAll(chunk);
      if (bytes.length > 64 * 1024) throw const HttpException('Unexpected answer from the network.');
    }
    return bytes;
  }
}

/// Headers for the little page the browser shows after sign-in: nothing cached, loaded or leaked.
void _secureHeaders(HttpResponse response) => response.headers
  ..set(HttpHeaders.cacheControlHeader, 'no-store')
  ..set('Referrer-Policy', 'no-referrer')
  ..set('X-Content-Type-Options', 'nosniff')
  ..set('X-Frame-Options', 'DENY')
  ..set('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'");
