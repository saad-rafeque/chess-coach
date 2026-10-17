import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/coach/llm/model_store.dart';
import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/data/event_validation.dart';
import 'package:chess_coach/data/game_record.dart';
import 'package:chess_coach/engine/analysis.dart';
import 'package:chess_coach/engine/chess_engine.dart';
import 'package:chess_coach/review/game_review.dart';
import 'package:chess_coach/sync/drive.dart';
import 'package:chess_coach/sync/google_auth.dart';
import 'package:chess_coach/sync/sync_service.dart';
import 'package:chess_coach/sync/token_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine_test.dart' show FakeUci;

AppEvent _event(String type, Map<String, dynamic> data, {String id = 'abc123'}) =>
    AppEvent(id: id, type: type, time: DateTime.utc(2026, 10), device: 'd', data: data);

const _game = {
  'side': 'white',
  'elo': 800,
  'moves': ['e2e4', 'e7e5', 'g1f3'],
  'result': '*',
  'ending': '',
  'grades': {'0': 'best', '2': 'good'},
};

void main() {
  group('event validation', () {
    test('accepts what the app writes', () {
      expect(isValidEvent(_event('game', _game)), isTrue);
      expect(
          isValidEvent(_event('review', {
            'game': 'g1',
            'scores': [
              {'cp': 20},
              {'cp': 30},
              {'mate': -2},
            ],
            'best': ['e2e4', null, 'e7e8q'],
          })),
          isTrue);
      expect(
          isValidEvent(_event('puzzle',
              {'id': '00sHx', 'solved': true, 'puzzleRating': 1450, 'themes': ['fork', 'short'], 'rated': true})),
          isTrue);
      expect(
          isValidEvent(_event('lesson',
              {'lesson': 'opening-principles', 'step': 2, 'steps': 8, 'area': 'openings', 'level': 600, 'solved': false})),
          isTrue);
      expect(isValidEvent(_event('card', {'id': 'lesson:a:1', 'kind': 'lesson', 'grade': 3})), isTrue);
      expect(
          isValidEvent(_event('activity',
              {'kind': 'puzzles', 'x': [1.0, 0.2, 0.0, 1.0, 0.5], 'reward': 0.6, 'minutes': 10, 'area': 'tactics'})),
          isTrue);
      expect(isValidEvent(_event('from_a_newer_version', {'anything': 1})), isTrue, reason: 'kept for sync');
    });

    test('rejects damaged or tampered events', () {
      Map<String, dynamic> game(Map<String, dynamic> change) => {..._game, ...change};
      for (final (what, e) in [
        ('illegal move', _event('game', game({'moves': ['e2e5']}))),
        ('not a move', _event('game', game({'moves': ['position startpos']}))),
        ('moves not a list', _event('game', game({'moves': 'e2e4'}))),
        ('grade past the end', _event('game', game({'grades': {'9': 'best'}}))),
        ('unknown grade', _event('game', game({'grades': {'0': 'genius'}}))),
        ('elo out of range', _event('game', game({'elo': 99999}))),
        ('scores and moves differ', _event('review', {'game': 'g', 'scores': [{'cp': 1}], 'best': [null, null]})),
        ('score not a number', _event('review', {'game': 'g', 'scores': [{'cp': 'x'}], 'best': [null]})),
        ('puzzle without id', _event('puzzle', {'solved': true})),
        ('absurd rating', _event('puzzle', {'id': 'p', 'puzzleRating': 1e12})),
        ('card grade', _event('card', {'id': 'c', 'grade': 7})),
        ('lesson step type', _event('lesson', {'lesson': 'l', 'step': '1'})),
        ('activity features', _event('activity', {'kind': 'game', 'x': ['a']})),
        ('id with a path', _event('puzzle', {'id': 'p'}, id: '../../etc')),
        ('huge event', _event('note', {'text': 'x' * (maxEventChars + 1)})),
      ]) {
        expect(isValidEvent(e), isFalse, reason: what);
      }
      expect(parseEvent({'id': 'a', 'type': 'puzzle'}), isNull, reason: 'missing fields');
      expect(parseEvent('not a map'), isNull);
    });

    test('merge and load skip bad events and keep the rest', () async {
      final store = EventStore.memory();
      final added = await store.merge([
        _event('puzzle', {'id': 'good'}, id: 'e1'),
        _event('game', {'moves': ['e2e5']}, id: 'e2'),
      ]);
      expect(added, 1);
      expect(store.events.single.id, 'e1');

      final dir = await Directory.systemTemp.createTemp('events');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/events.jsonl')
        ..writeAsStringSync([
          jsonEncode(_event('puzzle', {'id': 'ok'}, id: 'a1').toJson()),
          '{"id": "a2", "type": "game", "time": "2026-10-01T00:00:00Z", "data": {"moves": ["a1a8"]}}',
          'garbage',
          jsonEncode(_event('game', _game, id: 'a3').toJson()),
        ].join('\n'));
      final loaded = await EventStore.openFile(file, device: 'd');
      expect(loaded.events.map((e) => e.id), ['a1', 'a3']);
    });

    test('a review shorter than its game does not break the review screen', () {
      final game = GameRecord.fromEvent(_event('game', _game));
      final review = buildReview(game, const GameAnalysis(scores: [Score.cp(20), Score.cp(30)], best: [null, null]));
      expect(review.moves, hasLength(1));
    });
  });

  group('sync file', () {
    List<int> encode(Object json) => gzip.encode(utf8.encode(jsonEncode(json)));

    test('keeps the good events of a partly damaged file', () {
      final p = SyncPayload.decode(encode({
        'version': 1,
        'events': [
          _event('puzzle', {'id': 'ok'}, id: 'a1').toJson(),
          {'id': 'a2', 'type': 'card', 'time': '2026-10-01T00:00:00Z', 'data': {'id': 'c', 'grade': 99}},
          42,
        ],
        'settings': {'theme': 'light'},
        'settingsChanged': DateTime.now().add(const Duration(days: 365)).toUtc().toIso8601String(),
      }));
      expect(p.events.map((e) => e.id), ['a1']);
      expect(p.settings, {'theme': 'light'});
      expect(p.settingsChanged, isNull, reason: 'a date in the future would win forever');
    });

    test('rejects files that are not sync files or unpack too large', () {
      expect(() => SyncPayload.decode(encode([1, 2])), throwsFormatException);
      expect(() => SyncPayload.decode(utf8.encode('plain text')), throwsA(anything));
      final bomb = gzip.encode(List<int>.filled(2 << 20, 32));
      expect(bomb.length, lessThan(64 * 1024));
      expect(() => SyncPayload.decode(bomb, maxJson: 1 << 20), throwsFormatException);
    });

    test('settings from another device are checked', () {
      final s = AppSettings.memory();
      s.applySync({'theme': 'nope', 'coords': 'yes', 'hints': false, 'coachElo': 100000}, DateTime.now().toUtc());
      expect(s.theme, AppTheme.dark);
      expect(s.showCoordinates, isTrue);
      expect(s.trainingHints, isFalse);
      expect(s.coachElo, 3200);
      s.applySync({'coachElo': 'strong'}, DateTime.now().toUtc().add(const Duration(seconds: 1)));
      expect(s.coachElo, 3200);
    });
  });

  group('sign-in', () {
    late HttpServer tokenServer;
    late List<Map<String, String>> forms;
    String scope = driveAppDataScope;

    setUp(() async {
      forms = [];
      scope = driveAppDataScope;
      tokenServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      tokenServer.listen((req) async {
        forms.add(Uri.splitQueryString(await utf8.decoder.bind(req).join()));
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'access_token': 'acc', 'expires_in': 3600, 'refresh_token': 'ref', 'scope': scope}));
        await req.response.close();
      });
    });

    tearDown(() => tokenServer.close(force: true));

    GoogleAuth auth() => GoogleAuth(const OAuthConfig(clientId: 'cid', clientSecret: 'sec'),
        tokenEndpoint: 'http://127.0.0.1:${tokenServer.port}/token');

    Future<HttpClientResponse> visit(String url) async => (await HttpClient().getUrl(Uri.parse(url))).close();

    test('a request without our state can neither sign in nor cancel', () async {
      late HttpClientResponse forged;
      final real = Completer<HttpClientResponse>();
      final refresh = await auth().signIn((url) async {
        final q = url.queryParameters;
        unawaited(() async {
          // Another program or web page tries to slip in its own code, then to cancel.
          forged = await visit('${q['redirect_uri']}/?code=evil&state=guess');
          await visit('${q['redirect_uri']}/?error=access_denied');
          await visit('${q['redirect_uri']}/favicon.ico');
          real.complete(await visit('${q['redirect_uri']}/?code=good&state=${q['state']}'));
        }());
        return true;
      });
      expect(refresh, 'ref');
      expect(forms.single['code'], 'good');
      expect(forged.statusCode, HttpStatus.badRequest);
      final page = await real.future;
      expect(page.headers.value('content-security-policy'), contains("default-src 'none'"));
      expect(page.headers.value('cache-control'), 'no-store');
    });

    test('says so when the Drive permission was unticked', () async {
      scope = 'openid email';
      final f = auth().signIn((url) async {
        final q = url.queryParameters;
        unawaited(visit('${q['redirect_uri']}/?code=c&state=${q['state']}'));
        return true;
      });
      await expectLater(f, throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('tick'))));
    });
  });

  group('sign-in storage', () {
    test('the token file is private to this user', () async {
      final dir = await Directory.systemTemp.createTemp('tokens');
      addTearDown(() => dir.delete(recursive: true));
      final store = FileTokenStore(() async => dir);
      expect(await store.read(), isNull);
      await store.write('secret-refresh');
      expect(await store.read(), 'secret-refresh');
      final file = File('${dir.path}/${FileTokenStore.fileName}');
      if (Platform.isLinux || Platform.isMacOS) expect(file.statSync().modeString(), 'rw-------');
      await store.write(null);
      expect(file.existsSync(), isFalse);
    });

    test('a token from an older version moves out of the preferences', () async {
      final settings = AppSettings.memory()..writeValue('syncRefreshToken', 'old');
      final tokens = MemoryTokenStore();
      final s = SyncService(
        store: EventStore.memory(),
        settings: settings,
        config: const OAuthConfig(clientId: 'id', clientSecret: 's'),
        folder: (_) => throw const SocketException('offline'),
        tokens: tokens,
        retryDelays: const [],
      );
      await s.sync();
      expect(tokens.token, 'old');
      expect(settings.readValue('syncRefreshToken'), isNull);
      expect(s.connected, isTrue);
    });
  });

  group('downloads and engine', () {
    late Directory dir;
    late HttpServer server;
    final body = List<int>.generate(1000, (i) => i % 251);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('models');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        if (req.uri.path == '/hop') {
          await req.response.redirect(Uri.parse('http://127.0.0.1:${server.port}/model'));
        } else {
          req.response.add(body);
          await req.response.close();
        }
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    ModelSpec spec(String path) => ModelSpec(
        id: 't',
        name: 'T',
        detail: '',
        fileName: 't.gguf',
        url: 'http://127.0.0.1:${server.port}$path',
        bytes: body.length,
        sha256: sha256.convert(body).toString());

    test('a model download never follows a link off HTTPS', () async {
      final store = ModelStore(directory: () async => dir);
      await store.download(spec('/hop'));
      expect(store.status(spec('/hop')), ModelStatus.failed);
      expect(store.error(spec('/hop')), contains('not secure'));
    });

    test('a model file replaced after its check is checked again before use', () async {
      final m = explainerModels.first;
      final f = File('${dir.path}/${m.fileName}').openSync(mode: FileMode.write)..truncateSync(m.bytes);
      f.closeSync();
      final store = ModelStore(directory: () async => dir);
      await store.refresh();
      expect(store.status(m), ModelStatus.failed, reason: 'same size, wrong content');
      expect(store.error(m), contains('changed or damaged'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('the engine refuses a position that would smuggle in commands', () async {
      final uci = FakeUci({});
      final engine = ChessEngine(uci);
      await expectLater(engine.analyse('8/8/8/8/8/8/8/8 w - - 0 1\nquit'), throwsArgumentError);
      expect(uci.sent.where((c) => c.startsWith('position')), isEmpty);
    });
  });
}
