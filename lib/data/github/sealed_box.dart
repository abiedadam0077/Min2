import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/api.dart';
import 'package:pinenacl/x25519.dart';

/// Encrypts a value for GitHub Actions secrets.
///
/// GitHub requires libsodium `crypto_box_seal` output, base64 encoded, using the repository
/// public key. pinenacl implements the same sealed-box construction.
String encryptForGitHubSecret({required String base64PublicKey, required String plaintext}) {
  final publicKey = PublicKey(base64Decode(base64PublicKey));
  final sealed = SealedBox(publicKey).encrypt(Uint8List.fromList(utf8.encode(plaintext)));
  return base64Encode(sealed);
}
