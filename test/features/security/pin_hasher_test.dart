import 'dart:convert';
import 'dart:math';

import 'package:bkdash_sanitary_ware/features/security/data/pin_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String _pbkdf2(String password, String salt, int iterations, int length) =>
    _hex(
      PinHasher.pbkdf2(
        password: utf8.encode(password),
        salt: utf8.encode(salt),
        iterations: iterations,
        keyLength: length,
      ),
    );

void main() {
  group('PBKDF2-HMAC-SHA256 reference vectors', () {
    test('1 iteration', () {
      expect(
        _pbkdf2('password', 'salt', 1, 32),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('2 iterations', () {
      expect(
        _pbkdf2('password', 'salt', 2, 32),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('4096 iterations', () {
      expect(
        _pbkdf2('password', 'salt', 4096, 32),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });

    test('a key longer than one block (64 bytes)', () {
      expect(
        _pbkdf2('passwd', 'salt', 1, 64),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
        '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
      );
    });
  });

  group('PinHasher', () {
    test('a salt is 16 random bytes in base64', () {
      final salt = PinHasher.generateSalt(Random(1));
      expect(base64Decode(salt), hasLength(16));
      expect(PinHasher.generateSalt() == PinHasher.generateSalt(), isFalse);
    });

    test('verify accepts the right PIN and rejects a wrong one', () {
      final salt = PinHasher.generateSalt();
      final hash = PinHasher.hash('1234', salt, iterations: 50);

      expect(PinHasher.verify('1234', salt, hash, iterations: 50), isTrue);
      expect(PinHasher.verify('1235', salt, hash, iterations: 50), isFalse);
      expect(PinHasher.verify('', salt, hash, iterations: 50), isFalse);
    });

    test('the same PIN gives different hashes with different salts', () {
      final a = PinHasher.hash(
        '1234',
        PinHasher.generateSalt(),
        iterations: 50,
      );
      final b = PinHasher.hash(
        '1234',
        PinHasher.generateSalt(),
        iterations: 50,
      );
      expect(a == b, isFalse);
      expect(a, hasLength(64));
    });
  });
}
