import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openpanel_flutter/src/models/batch_payload.dart';
import 'package:openpanel_flutter/src/models/post_event_payload.dart';
import 'package:openpanel_flutter/src/models/update_profile_payload.dart';
import 'package:openpanel_flutter/src/services/openpanel_http_client.dart';

/// Logger output that silently discards all lines.
class _SilentOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockDio extends Mock implements Dio {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a fake [Response] that Dio would return.
Response<Map<String, dynamic>> _mockResponse({
  required int statusCode,
  required Map<String, dynamic> data,
}) {
  return Response<Map<String, dynamic>>(
    requestOptions: RequestOptions(path: '/track/batch'),
    statusCode: statusCode,
    data: data,
  );
}

void main() {
  late MockDio mockDio;
  late OpenpanelHttpClient client;
  final logger = Logger(printer: PrettyPrinter(), output: _SilentOutput());

  setUp(() {
    mockDio = MockDio();
    client = OpenpanelHttpClient.withDio(mockDio, logger: logger);

    // Provide a default fallback for interceptors getter (needed by Dio.post)
    when(() => mockDio.interceptors).thenReturn(Interceptors());
  });

  // -------------------------------------------------------------------------
  // batch()
  // -------------------------------------------------------------------------
  group('OpenpanelHttpClient.batch', () {
    final event1 = const BatchedEvent(
      type: 'track',
      payload: {'name': 'page_view', 'profileId': 'u1'},
    );
    final event2 = const BatchedEvent(
      type: 'identify',
      payload: {'profileId': 'u2'},
    );

    test('POSTs to /track/batch with correct body shape', () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/track/batch',
            data: any(named: 'data'),
          )).thenAnswer((_) async => _mockResponse(
            statusCode: 202,
            data: {'accepted': 2, 'rejected': []},
          ));

      await client.batch([event1, event2]);

      final captured = verify(() => mockDio.post<Map<String, dynamic>>(
            '/track/batch',
            data: captureAny(named: 'data'),
          )).captured;

      final body = captured.first as Map<String, dynamic>;
      expect(body.containsKey('events'), isTrue);
      final events = body['events'] as List;
      expect(events.length, 2);
      expect(events[0], {'type': 'track', 'payload': event1.payload});
      expect(events[1], {'type': 'identify', 'payload': event2.payload});
    });

    test('returns BatchResponse(accepted: 2, rejected: []) on happy-path 202',
        () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/track/batch',
            data: any(named: 'data'),
          )).thenAnswer((_) async => _mockResponse(
            statusCode: 202,
            data: {'accepted': 2, 'rejected': []},
          ));

      final response = await client.batch([event1, event2]);

      expect(response.accepted, 2);
      expect(response.rejected, isEmpty);
    });

    test('returns BatchResponse with rejections parsed correctly', () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/track/batch',
            data: any(named: 'data'),
          )).thenAnswer((_) async => _mockResponse(
            statusCode: 202,
            data: {
              'accepted': 1,
              'rejected': [
                {'index': 1, 'reason': 'validation', 'error': 'bad payload'},
              ],
            },
          ));

      final response = await client.batch([event1, event2]);

      expect(response.accepted, 1);
      expect(response.rejected.length, 1);
      expect(response.rejected.first.index, 1);
      expect(response.rejected.first.reason, 'validation');
      expect(response.rejected.first.error, 'bad payload');
    });

    test('throws BatchTransportError on DioException (non-2xx response)',
        () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/track/batch',
            data: any(named: 'data'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/track/batch'),
        response: Response(
          requestOptions: RequestOptions(path: '/track/batch'),
          statusCode: 500,
        ),
        message: 'Internal Server Error',
        type: DioExceptionType.badResponse,
      ));

      expect(
        () => client.batch([event1]),
        throwsA(isA<BatchTransportError>().having(
          (e) => e.statusCode,
          'statusCode',
          500,
        )),
      );
    });

    test('throws BatchTransportError on network failure (no status code)',
        () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/track/batch',
            data: any(named: 'data'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/track/batch'),
        message: 'Network unreachable',
        type: DioExceptionType.connectionError,
      ));

      expect(
        () => client.batch([event1]),
        throwsA(isA<BatchTransportError>().having(
          (e) => e.statusCode,
          'statusCode',
          isNull,
        )),
      );
    });

    test('503 response → throws BatchTransportError with isTransient=true',
        () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/track/batch',
            data: any(named: 'data'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/track/batch'),
        response: Response(
          requestOptions: RequestOptions(path: '/track/batch'),
          statusCode: 503,
        ),
        message: 'Service Unavailable',
        type: DioExceptionType.badResponse,
      ));

      expect(
        () => client.batch([event1]),
        throwsA(isA<BatchTransportError>()
            .having((e) => e.statusCode, 'statusCode', 503)
            .having((e) => e.isTransient, 'isTransient', isTrue)),
      );
    });

    test('400 response → throws BatchTransportError with isTransient=false',
        () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/track/batch',
            data: any(named: 'data'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/track/batch'),
        response: Response(
          requestOptions: RequestOptions(path: '/track/batch'),
          statusCode: 400,
        ),
        message: 'Bad Request',
        type: DioExceptionType.badResponse,
      ));

      expect(
        () => client.batch([event1]),
        throwsA(isA<BatchTransportError>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.isTransient, 'isTransient', isFalse)),
      );
    });

    test(
        'DioException with connectionError type → throws BatchTransportError with isTransient=true',
        () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/track/batch',
            data: any(named: 'data'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/track/batch'),
        message: 'Connection refused',
        type: DioExceptionType.connectionError,
      ));

      expect(
        () => client.batch([event1]),
        throwsA(isA<BatchTransportError>()
            .having((e) => e.isTransient, 'isTransient', isTrue)),
      );
    });

    test(
        'DioException with badResponse + 401 → throws BatchTransportError with isTransient=false',
        () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/track/batch',
            data: any(named: 'data'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/track/batch'),
        response: Response(
          requestOptions: RequestOptions(path: '/track/batch'),
          statusCode: 401,
        ),
        message: 'Unauthorized',
        type: DioExceptionType.badResponse,
      ));

      expect(
        () => client.batch([event1]),
        throwsA(isA<BatchTransportError>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.isTransient, 'isTransient', isFalse)),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Smoke test: existing single-event path still routes correctly
  // -------------------------------------------------------------------------
  group('legacy single-event paths (smoke test)', () {
    test('updateProfile calls /track with type=identify', () async {
      when(() => mockDio.post<dynamic>(
            '/track',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/track'),
            statusCode: 200,
          ));

      client.updateProfile(
        payload: UpdateProfilePayload(profileId: 'u1', properties: {}),
        stateProperties: {},
      );

      // Give the fire-and-forget a tick to run
      await Future<void>.delayed(Duration.zero);

      final captured = verify(() => mockDio.post<dynamic>(
            '/track',
            data: captureAny(named: 'data'),
          )).captured;

      final body = captured.first as Map<String, dynamic>;
      expect(body['type'], 'identify');
    });

    test('event() omits profileId from /track payload when user is logged out',
        () async {
      when(() => mockDio.post<dynamic>(
            '/track',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/track'),
            statusCode: 200,
            data: 'ok',
          ));

      await client.event(
        payload: PostEventPayload(
          name: 'screen_view',
          timestamp: '2026-01-01T00:00:00.000Z',
          deviceId: 'device-1',
          profileId: null,
        ),
      );

      final captured = verify(() => mockDio.post<dynamic>(
            '/track',
            data: captureAny(named: 'data'),
          )).captured;

      final body = captured.first as Map<String, dynamic>;
      final payload = body['payload'] as Map<String, dynamic>;
      expect(payload.containsKey('profileId'), isFalse,
          reason: 'profileId must not be sent to the server when user is '
              'logged out — server resolves identity via deviceId');
    });

    test('event() includes profileId in /track payload when user is logged in',
        () async {
      when(() => mockDio.post<dynamic>(
            '/track',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/track'),
            statusCode: 200,
            data: 'ok',
          ));

      await client.event(
        payload: PostEventPayload(
          name: 'screen_view',
          timestamp: '2026-01-01T00:00:00.000Z',
          deviceId: 'device-1',
          profileId: 'user-123',
        ),
      );

      final captured = verify(() => mockDio.post<dynamic>(
            '/track',
            data: captureAny(named: 'data'),
          )).captured;

      final body = captured.first as Map<String, dynamic>;
      final payload = body['payload'] as Map<String, dynamic>;
      expect(payload['profileId'], 'user-123');
    });
  });
}
