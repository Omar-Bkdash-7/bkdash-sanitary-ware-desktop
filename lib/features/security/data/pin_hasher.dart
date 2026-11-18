import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Salted PBKDF2-HMAC-SHA256 hashing of the PIN, so the PIN itself is never
/// stored on the device.
abstract final class PinHasher {
  /// Work factor: how many times the hash is repeated for every guess.
  static const int defaultIterations = 10000;

  static const int _saltBytes = 16;
  static const int _keyBytes = 32;

  /// A new random salt (base64 text).
  static String generateSalt([Random? random]) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(_saltBytes, (_) => source.nextInt(256));
    return base64Encode(bytes);
  }

  /// The hash of [pin] (hex text).
  static String hash(
    String pin,
    String salt, {
    int iterations = defaultIterations,
  }) {
    final key = pbkdf2(
      password: utf8.encode(pin),
      salt: base64Decode(salt),
      iterations: iterations,
      keyLength: _keyBytes,
    );
    return _hex(key);
  }

  /// Compares in constant time so the answer time does not leak how many
  /// characters were right.
  static bool verify(
    String pin,
    String salt,
    String expectedHash, {
    int iterations = defaultIterations,
  }) {
    final candidate = hash(pin, salt, iterations: iterations);
    if (candidate.length != expectedHash.length) return false;
    var difference = 0;
    for (var i = 0; i < candidate.length; i++) {
      difference |= candidate.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return difference == 0;
  }

  /// PBKDF2 with HMAC-SHA256 (RFC 8018).
  static Uint8List pbkdf2({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int keyLength,
  }) {
    final hmac = Hmac(sha256, password);
    const blockLength = 32; // SHA-256 output size
    final blocks = (keyLength + blockLength - 1) ~/ blockLength;
    final output = BytesBuilder();

    for (var block = 1; block <= blocks; block++) {
      var u = hmac.convert(<int>[
        ...salt,
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ]).bytes;
      final t = List<int>.of(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      output.add(t);
    }
    return Uint8List.fromList(output.toBytes().sublist(0, keyLength));
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
