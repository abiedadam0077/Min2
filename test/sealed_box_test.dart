import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/api.dart';
import 'package:pinenacl/x25519.dart';
import 'package:voxelops/data/github/sealed_box.dart';

/// Vector generated with PyNaCl (libsodium crypto_box_seal) for the key seed 0x00..0x1f.
const String _libsodiumCipher =
    'rU8B9rafGBrgWrzTBC6g/o0KY8YPrhTCO0vwQ1mCZlwVp7rE6iWBNIck7Wp1DyUgsSPBGpU/Su0QYrIj5BhgT0hTfZEaNaBs';
const String _plaintext = 'voxelops-secret-value-é';

PrivateKey _key() => PrivateKey(Uint8List.fromList(List<int>.generate(32, (i) => i)));

void main() {
  test('decrypts a libsodium sealed box produced by PyNaCl', () {
    final plain = SealedBox(_key()).decrypt(Uint8List.fromList(base64Decode(_libsodiumCipher)));
    expect(utf8.decode(plain), _plaintext);
  });

  test('encryptForGitHubSecret produces a sealed box the recipient can open', () {
    final key = _key();
    final publicB64 = base64Encode(key.publicKey.asTypedList);
    final sealed = encryptForGitHubSecret(base64PublicKey: publicB64, plaintext: 'hello voxel');
    expect(base64Decode(sealed).length, 32 + 16 + 'hello voxel'.length);
    expect(utf8.decode(SealedBox(key).decrypt(Uint8List.fromList(base64Decode(sealed)))), 'hello voxel');
  });
}
