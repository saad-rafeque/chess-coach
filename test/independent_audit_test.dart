import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chess_coach/data/event_store.dart';
import 'package:chess_coach/engine/chess_engine.dart';
import 'package:chess_coach/engine/uci_process.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'engine failure before readyok is handled by the search caller',
    () async {
      final process = _ClosesBeforeReady();
      final engine = ChessEngine(process);
      await expectLater(
        engine.analyse('8/8/8/8/8/8/4K3/7k w - - 0 1'),
        throwsA(anything),
      );
      expect(engine.isClosed, isTrue);
    },
  );

  test('new progress survives a crash-truncated final history line', () async {
    final dir = await Directory.systemTemp.createTemp('chess-truncated');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/events.jsonl');
    await file.writeAsString('{"id":"unfinished');
    final store = await EventStore.openFile(file, device: 'test');
    await store.add('puzzle', {'id': 'p1'}, id: 'new-progress');
    final restored = await EventStore.openFile(file, device: 'test');
    expect(restored.events.map((e) => e.id), ['new-progress']);
    expect(restored.storageError, isNotNull);
  });

  test('malformed UTF-8 does not hide later valid progress', () async {
    final dir = await Directory.systemTemp.createTemp('chess-corrupt');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/events.jsonl');
    final good = AppEvent(
      id: 'good',
      type: 'puzzle',
      time: DateTime.utc(2020),
      device: 'test',
      data: const {'id': 'p1'},
    );
    await file.writeAsBytes([
      0xff,
      0xfe,
      10,
      ...utf8.encode('${jsonEncode(good.toJson())}\n'),
    ]);
    final restored = await EventStore.openFile(file, device: 'test');
    expect(restored.events.map((e) => e.id), ['good']);
    expect(restored.storageError, isNotNull);
  });

  test('concurrent local and sync appends retain every record', () async {
    final dir = await Directory.systemTemp.createTemp('chess-concurrent');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/events.jsonl');
    final store = await EventStore.openFile(file, device: 'test');
    await Future.wait([
      for (var i = 0; i < 30; i++)
        store.add('puzzle', {'id': 'p$i'}, id: 'local-$i'),
      store.merge([
        for (var i = 0; i < 30; i++)
          AppEvent(
            id: 'remote-$i',
            type: 'puzzle',
            time: DateTime.utc(2020),
            device: 'other',
            data: {'id': 'p$i'},
          ),
      ]),
    ]);
    final restored = await EventStore.openFile(file, device: 'test');
    expect(restored.events, hasLength(60));
    expect(restored.storageError, isNull);
  });

  test('byte-wise recovery preserves valid Unicode history', () async {
    final dir = await Directory.systemTemp.createTemp('chess-unicode');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/events.jsonl');
    final store = await EventStore.openFile(file, device: 'test');
    final text = 'اردو ♟️ ${'棋' * 60000}';
    await store.add('notes', {'text': text}, id: 'unicode');
    final restored = await EventStore.openFile(file, device: 'test');
    expect(restored.events.single.data['text'], text);
    expect(restored.storageError, isNull);
  });
}

class _ClosesBeforeReady implements UciProcess {
  final _out = StreamController<String>.broadcast();
  @override
  Stream<String> get lines => _out.stream;
  @override
  void send(String command) {
    if (command == 'isready') scheduleMicrotask(_out.close);
  }

  @override
  Future<void> close() => _out.close();
}
