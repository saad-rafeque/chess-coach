import 'dart:async';
import 'dart:io';

import 'package:chess_coach/app/settings.dart';
import 'package:chess_coach/coach/llm/coach_voice.dart';
import 'package:chess_coach/coach/llm/model_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGenerator implements TextGenerator {
  _FakeGenerator(this.answer);

  String Function(String facts) answer;
  int calls = 0;
  bool disposed = false;

  @override
  Future<String> generate(List<(String, String)> messages, {int maxTokens = 80}) async {
    calls++;
    return answer(messages.last.$2.replaceFirst('Note: ', ''));
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  group('acceptRephrase', () {
    const facts = 'Now Black can take your knight on f6. Better was Nd5.';

    test('keeps a faithful rewording', () {
      expect(acceptRephrase(facts, ' "Careful! Black can win your knight on f6. Nd5 was stronger." '),
          'Careful! Black can win your knight on f6. Nd5 was stronger.');
      expect(acceptRephrase(facts, 'Note: Black can grab the knight on f6; Nd5 was better.'), isNotNull);
    });

    test('rejects anything the facts do not say', () {
      expect(acceptRephrase(facts, 'Black can take your knight on f6. Nd5 or Nc3 was better.'), isNull,
          reason: 'new move');
      expect(acceptRephrase(facts, 'Black can take your knight on g6. Nd5 was better.'), isNull, reason: 'new square');
      expect(acceptRephrase(facts, 'Black can take your knight on f6.'), isNull, reason: 'dropped the better move');
      expect(acceptRephrase(facts, 'Black can take your queen on f6. Nd5 was better.'), isNull, reason: 'new piece');
      expect(acceptRephrase(facts, 'White can take your knight on f6. Nd5 was better.'), isNull, reason: 'new side');
      expect(acceptRephrase(facts, 'In 2 moves Black takes your knight on f6. Nd5 was better.'), isNull,
          reason: 'new number');
      expect(acceptRephrase(facts, ''), isNull);
      expect(acceptRephrase(facts, 'Nd5 was better, nice try.'), isNull, reason: 'lost the knight on f6');
      expect(acceptRephrase('This allows checkmate in 2. Better was Kh1.', 'Not bad, but Kh1 was even better.'), isNull,
          reason: 'lost the mate threat');
      expect(acceptRephrase('There was a stronger move. Better was c5.', 'Correct, c5 was the stronger move.'), isNull,
          reason: 'praise for an error');
      expect(acceptRephrase(facts, "I'm sorry, you mentioned Nd5 and f6 for the knight. Could you clarify?"), isNull,
          reason: 'talks about the task');
      expect(acceptRephrase(facts, 'Nd5 f6 knight Black. ' * 20), isNull, reason: 'too long');
    });

    test('mate wording may vary', () {
      expect(acceptRephrase('This allows checkmate in 2. Better was Kh1.', 'Watch out: this lets them mate in 2. Kh1 was safer.'),
          isNotNull);
    });
  });

  group('CoachVoice', () {
    late Directory dir;
    late AppSettings settings;
    late ModelStore models;
    late _FakeGenerator generator;
    var loads = 0;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('voice');
      // A sparse file of the right size stands in for the downloaded model.
      final spec = explainerModels.first;
      final f = File('${dir.path}/${spec.fileName}').openSync(mode: FileMode.write)..truncateSync(spec.bytes);
      f.closeSync();
      settings = AppSettings.memory();
      models = ModelStore(directory: () async => dir);
      await models.markVerified(spec);
      await models.refresh();
      generator = _FakeGenerator((facts) => 'Oops! $facts');
      loads = 0;
    });

    tearDown(() => dir.delete(recursive: true));

    CoachVoice voice({Duration timeout = const Duration(seconds: 1), bool fail = false}) => CoachVoice(
          settings: settings,
          models: models,
          timeout: timeout,
          loader: (file) async {
            loads++;
            if (fail) throw StateError('no runtime');
            return generator;
          },
        );

    test('rewords explanations once a model is installed, and caches them', () async {
      final v = voice();
      expect(v.active, isTrue);
      const facts = 'You missed Qxf7#, which wins.';
      expect(await v.polish(facts), 'Oops! You missed Qxf7#, which wins.');
      expect(await v.polish(facts), 'Oops! You missed Qxf7#, which wins.');
      expect(generator.calls, 1);
      expect(loads, 1);
    });

    test('keeps the template when the model invents something', () async {
      generator.answer = (facts) => 'Try Qh5 next time.';
      expect(await voice().polish('Better was Nf3.'), isNull);
    });

    test('is silent when switched off or without a model', () async {
      settings.friendlyVoice = false;
      expect(await voice().polish('Better was Nf3.'), isNull);
      settings.friendlyVoice = true;
      await models.delete(explainerModels.first);
      expect(voice().active, isFalse);
      expect(generator.calls, 0);
    });

    test('gives up quietly when the model is slow or cannot start', () async {
      generator.answer = (facts) => throw TimeoutException('slow');
      expect(await voice().polish('Better was Nf3.'), isNull);
      final broken = voice(fail: true);
      expect(await broken.polish('Better was Nf3.'), isNull);
      expect(broken.failed, isTrue);
      expect(broken.active, isFalse);
    });

    test('frees the model when the voice is switched off', () async {
      final v = voice();
      await v.polish('Better was Nf3.');
      settings.friendlyVoice = false;
      await Future<void>.delayed(Duration.zero);
      expect(generator.disposed, isTrue);
    });
  });

  group('ModelStore', () {
    late Directory dir;
    late HttpServer server;
    final body = List<int>.generate(100000, (i) => i % 251);
    var rangeRequests = 0;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('models');
      rangeRequests = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        if (range != null) {
          rangeRequests++;
          final from = int.parse(range.split('=')[1].split('-')[0]);
          req.response.statusCode = HttpStatus.partialContent;
          req.response.add(body.sublist(from));
        } else {
          req.response.add(body);
        }
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    ModelSpec spec({String? hash}) => ModelSpec(
          id: 'test',
          name: 'Test',
          detail: '',
          fileName: 'test.gguf',
          url: 'http://127.0.0.1:${server.port}/test.gguf',
          bytes: body.length,
          sha256: hash ?? sha256.convert(body).toString(),
        );

    test('downloads and verifies a model', () async {
      final store = ModelStore(directory: () async => dir);
      final m = spec();
      await store.download(m);
      expect(store.status(m), ModelStatus.ready);
      expect(File('${dir.path}/test.gguf').readAsBytesSync(), body);
      await store.delete(m);
      expect(store.status(m), ModelStatus.absent);
      expect(File('${dir.path}/test.gguf').existsSync(), isFalse);
    });

    test('resumes a partial download', () async {
      File('${dir.path}/test.gguf.part').writeAsBytesSync(body.sublist(0, 40000));
      final store = ModelStore(directory: () async => dir);
      await store.download(spec());
      expect(rangeRequests, 1);
      expect(store.status(spec()), ModelStatus.ready);
    });

    test('rejects a damaged file', () async {
      final store = ModelStore(directory: () async => dir);
      final m = spec(hash: '0' * 64);
      await store.download(m);
      expect(store.status(m), ModelStatus.failed);
      expect(store.error(m), contains('damaged'));
      expect(File('${dir.path}/test.gguf').existsSync(), isFalse);
    });
  });
}
