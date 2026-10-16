import 'dart:io';

import 'package:chess_coach/app/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appVersion matches pubspec.yaml', () {
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    expect(line.split(' ')[1].split('+').first, appVersion);
  });
}
