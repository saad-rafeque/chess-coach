// Checks the llama.cpp runtime that llamadart's build hook downloaded (it does not verify it
// itself) against pinned SHA-256 digests, so a replaced release asset upstream fails the build
// instead of shipping. Run after `flutter build`; pass the bundles that build must have used.
// Usage: dart run tool/check_native_bundles.dart linux-x64 [android-arm64 ...]
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// llamadart 0.11.1's runtime release (github.com/leehack/llamadart-native).
const tag = 'v0.5.0-2';
const pinned = {
  'linux-x64': '66b7983ea2c01c64a4d0adf5519c7e6cac09ab9ede2dc5ee7ad19f45634300fe',
  'windows-x64': 'de4687a5a4bd84ca19cd7e7f4452ad3d09b3f952100de3bb2ad012fad4615d7f',
  'android-arm64': 'ad5991df443e6600ffb6641e39b16d87ce685fa1f2bdac1eeb2f07c811048925',
  'android-x64': '374c7222ba36ad7eca6744ed30b75d6688bda364460d5ebee66ae3665bb5ab4f',
};

void main(List<String> required) {
  final config = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  final package = (config['packages'] as List).cast<Map<String, dynamic>>().firstWhere((p) => p['name'] == 'llamadart');
  var root = Uri.parse('${package['rootUri']}/');
  if (!root.isAbsolute) root = Directory.current.uri.resolve('.dart_tool/').resolveUri(root);
  final bundles = Directory.fromUri(root.resolve('.dart_tool/llamadart/native_bundles/$tag/'));

  var failed = false;
  final found = <String>{};
  if (bundles.existsSync()) {
    for (final dir in bundles.listSync().whereType<Directory>()) {
      final name = dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final archive = File.fromUri(dir.uri.resolve('llamadart-native-$name-$tag.tar.gz'));
      if (!archive.existsSync()) continue;
      found.add(name);
      final digest = sha256.convert(archive.readAsBytesSync()).toString();
      if (pinned[name] == digest) {
        stdout.writeln('ok  $name');
      } else {
        stderr.writeln('BAD $name: got $digest, expected ${pinned[name] ?? 'no pinned digest'}');
        failed = true;
      }
    }
  }
  for (final name in required.where((n) => !found.contains(n))) {
    stderr.writeln('MISSING $name (looked in ${bundles.path})');
    failed = true;
  }
  if (failed) exit(1);
}
