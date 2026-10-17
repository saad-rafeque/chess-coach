import 'dart:async';
import 'dart:io';

import 'package:chess_coach/app/desktop_integration.dart';
import 'package:chess_coach/engine/chess_engine.dart';
import 'package:chess_coach/engine/engine_host.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine_test.dart' show FakeUci;

void main() {
  group('AppImage menu entry', () {
    test('quotes the path as the desktop entry spec asks', () {
      final exec = desktopEntry(r'/home/a b/x"y$z\w%.AppImage').split('\n').firstWhere((l) => l.startsWith('Exec='));
      expect(exec, r'Exec="/home/a b/x\\"y\\$z\\\\w%%.AppImage"');
    });

    test('adds the menu entry and icon once, and follows the AppImage when it moves', () async {
      final home = await Directory.systemTemp.createTemp('home');
      addTearDown(() => home.delete(recursive: true));
      final bundle = Directory('${home.path}/bundle/data')..createSync(recursive: true);
      File('${bundle.path}/app_icon.png').writeAsBytesSync([1, 2, 3]);
      Future<void> run(String appImage) => integrateAppImage(
          environment: {'HOME': home.path, 'APPIMAGE': appImage}, executable: '${home.path}/bundle/chess_coach');

      await run('/apps/ChessCoach.AppImage');
      final desktop = File('${home.path}/.local/share/applications/$linuxAppId.desktop');
      expect(desktop.readAsStringSync(), contains('Exec="/apps/ChessCoach.AppImage"'));
      expect(File('${home.path}/.local/share/icons/hicolor/512x512/apps/$linuxAppId.png').readAsBytesSync(), [1, 2, 3]);

      await run('/other/ChessCoach.AppImage');
      expect(desktop.readAsStringSync(), contains('Exec="/other/ChessCoach.AppImage"'));

      await integrateAppImage(environment: {'HOME': home.path}, executable: '${home.path}/bundle/chess_coach');
      expect(desktop.existsSync(), isTrue, reason: 'not an AppImage: nothing changes');
    });
  });

  group('engine start', () {
    test('a slow first start gets time, and a failed start is retried later', () async {
      var attempts = 0;
      final host = EngineHost(
        retryAfter: Duration.zero,
        starter: () async {
          attempts++;
          if (attempts == 1) throw TimeoutException('cold start');
          final uci = FakeUci({
            'uci': ['uciok'],
            'isready': ['readyok'],
          });
          return ChessEngine.start(process: uci);
        },
      );
      expect(await host.engine, isNull);
      expect(host.status.value, EngineStatus.unavailable);
      expect(await host.engine, isNotNull);
      expect(host.status.value, EngineStatus.ready);
      expect(attempts, 2);
    });

    test('an engine that never answers is closed, not left running', () async {
      final uci = _ClosingUci();
      await expectLater(
          ChessEngine.start(process: uci, startTimeout: const Duration(milliseconds: 50)), throwsA(isA<TimeoutException>()));
      expect(uci.closed, isTrue);
    });
  });
}

class _ClosingUci extends FakeUci {
  _ClosingUci() : super({});

  bool closed = false;

  @override
  Future<void> close() {
    closed = true;
    return super.close();
  }
}
