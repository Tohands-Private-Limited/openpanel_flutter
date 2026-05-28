import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/data.dart';
import 'package:uuid/v7.dart';

/// Generates a UUIDv7-based insert_id for event deduplication.
///
/// The 74 random bits of UUIDv7 are XOR'd with SHA-256(deviceId) so that
/// events from different physical devices cannot collide on the random
/// portion alone — they'd also need identical millisecond timestamps.
String generateInsertId(String? deviceId) {
  final random = Random.secure();
  final randomBytes = Uint8List(10);
  for (var i = 0; i < 10; i++) {
    randomBytes[i] = random.nextInt(256);
  }

  if (deviceId != null && deviceId.isNotEmpty) {
    final hashBytes = sha256.convert(utf8.encode(deviceId)).bytes;
    for (var i = 0; i < 10; i++) {
      randomBytes[i] ^= hashBytes[i];
    }
  }

  return const UuidV7().generate(options: V7Options(null, randomBytes));
}
