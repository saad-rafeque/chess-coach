import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart';

/// The public half of the release signing key.
///
/// GitHub Actions signs each release's `SHA256SUMS.txt` with the private half
/// (kept in the `RELEASE_SIGNING_KEY` secret); the updater only trusts
/// checksums whose signature this key verifies. A release published without
/// the private key — for example after a takeover of the GitHub account — can
/// therefore never install itself automatically; the app sends the player to
/// the release page instead. See tool/sign_release.dart.
const releaseSigningPublicKeyHex = '3baaab57b600371371e6852824cd06897568637a2ec2ea0559ea7e5f2a8936bb';

/// True when [signature] is a valid Ed25519 signature of [message] by
/// [publicKeyHex].
bool verifyReleaseSignature(List<int> message, List<int> signature, [String publicKeyHex = releaseSigningPublicKeyHex]) =>
    verify(
      PublicKey(hexBytes(publicKeyHex)),
      Uint8List.fromList(message),
      Uint8List.fromList(signature),
    );

List<int> hexBytes(String hex) =>
    [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
