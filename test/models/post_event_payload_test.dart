import 'package:flutter_test/flutter_test.dart';
import 'package:openpanel_flutter/src/models/post_event_payload.dart';

void main() {
  group('PostEventPayload.toJson', () {
    test('includes profileId when non-null', () {
      final payload = PostEventPayload(
        name: 'screen_view',
        timestamp: '2026-01-01T00:00:00.000Z',
        deviceId: 'device-1',
        profileId: 'user-123',
      );

      final json = payload.toJson();

      expect(json.containsKey('profileId'), isTrue);
      expect(json['profileId'], 'user-123');
    });

    test('omits profileId entirely when null (logged-out user)', () {
      final payload = PostEventPayload(
        name: 'screen_view',
        timestamp: '2026-01-01T00:00:00.000Z',
        deviceId: 'device-1',
        profileId: null,
      );

      final json = payload.toJson();

      expect(json.containsKey('profileId'), isFalse,
          reason: 'profileId must be absent from JSON when user is logged out — '
              'the server resolves identity via deviceId alone');
    });

    test('omits profileId when not provided (default null)', () {
      final payload = PostEventPayload(
        name: 'screen_view',
        timestamp: '2026-01-01T00:00:00.000Z',
        deviceId: 'device-1',
      );

      final json = payload.toJson();

      expect(json.containsKey('profileId'), isFalse);
    });

    test('always includes deviceId, name, timestamp, and properties', () {
      final payload = PostEventPayload(
        name: 'tap_button',
        timestamp: '2026-01-01T00:00:00.000Z',
        deviceId: 'device-1',
        properties: {'screen': 'home'},
      );

      final json = payload.toJson();

      expect(json['name'], 'tap_button');
      expect(json['timestamp'], '2026-01-01T00:00:00.000Z');
      expect(json['deviceId'], 'device-1');
      expect(json['properties'], {'screen': 'home'});
    });
  });
}
