// Signs and checks release files with the Ed25519 release key.
//
// The app pins the public half of this key (lib/app/release_key.dart) and only
// trusts a release's SHA256SUMS.txt when its signature verifies, so a release
// published without the private key (for example by a takeover of the GitHub
// account) is never installed automatically.
//
// Usage:
//   dart run tool/sign_release.dart gen                     # print a new key pair (once)
//   RELEASE_SIGNING_KEY=<seed hex> dart run tool/sign_release.dart sign SHA256SUMS.txt
//   dart run tool/sign_release.dart verify SHA256SUMS.txt <public key hex> SHA256SUMS.txt.sig
//
// The seed is the RFC 8032 seed (32 bytes, hex), so the same key works with
// other Ed25519 tools if needed.
import 'dart:io';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart';

void main(List<String> args) {
  switch (args.firstOrNull) {
    case 'gen':
      final pair = generateKey();
      stdout.writeln('seed   ${hexEncode(seed(pair.privateKey))}   # keep secret: GitHub secret RELEASE_SIGNING_KEY');
      stdout.writeln('public ${hexEncode(pair.publicKey.bytes)}   # pin in lib/app/release_key.dart');
    case 'sign':
      if (args.length != 2) _usage();
      final seedHex = Platform.environment['RELEASE_SIGNING_KEY'];
      if (seedHex == null || seedHex.isEmpty) {
        stderr.writeln('Set RELEASE_SIGNING_KEY to the seed hex.');
        exit(1);
      }
      final privateKey = newKeyFromSeed(Uint8List.fromList(_hexBytes(seedHex)));
      final file = File(args[1]);
      final sig = sign(privateKey, Uint8List.fromList(file.readAsBytesSync()));
      final out = File('${file.path}.sig')..writeAsBytesSync(sig);
      stdout.writeln('wrote ${out.path} (${sig.length} bytes)');
    case 'verify':
      if (args.length != 4) _usage();
      final ok = verify(
        PublicKey(_hexBytes(args[2])),
        Uint8List.fromList(File(args[1]).readAsBytesSync()),
        Uint8List.fromList(File(args[3]).readAsBytesSync()),
      );
      stdout.writeln(ok ? 'signature OK' : 'BAD SIGNATURE');
      exit(ok ? 0 : 1);
    default:
      _usage();
  }
}

void _usage() {
  stderr.writeln('usage: sign_release.dart gen | sign <file> | verify <file> <public key hex> <sig file>');
  exit(1);
}

String hexEncode(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _hexBytes(String hex) =>
    [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
