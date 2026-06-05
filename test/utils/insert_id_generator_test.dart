import 'package:flutter_test/flutter_test.dart';
import 'package:openpanel_flutter/src/utils/insert_id_generator.dart';

void main() {
  // UUIDv7: version nibble is 7, variant nibble is 8/9/a/b.
  final uuidV7Pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  group('generateInsertId', () {
    test('produces a valid UUIDv7 string', () {
      final id = generateInsertId('device-123');
      expect(id, matches(uuidV7Pattern));
    });

    test('works with null deviceId', () {
      final id = generateInsertId(null);
      expect(id, matches(uuidV7Pattern));
    });

    test('works with empty deviceId', () {
      final id = generateInsertId('');
      expect(id, matches(uuidV7Pattern));
    });

    test('sequential IDs have non-decreasing timestamp prefixes', () {
      final a = generateInsertId('device-1');
      final b = generateInsertId('device-1');
      // Only the 48-bit millisecond timestamp (first 12 hex chars) is
      // ordered; the remaining bits are random and may sort either way
      // within the same millisecond.
      final timestampA = a.substring(0, 13); // 'xxxxxxxx-xxxx'
      final timestampB = b.substring(0, 13);
      expect(timestampB.compareTo(timestampA), greaterThanOrEqualTo(0));
    });

    test('1000 IDs for the same deviceId are all unique', () {
      final ids = List.generate(1000, (_) => generateInsertId('device-1'));
      expect(ids.toSet().length, 1000);
    });

    test('different deviceIds at same millisecond produce different IDs', () {
      final ids = {
        for (var i = 0; i < 50; i++) generateInsertId('device-$i'),
      };
      expect(ids.length, 50);
    });
  });
}
