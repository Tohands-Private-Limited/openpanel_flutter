import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openpanel_flutter/src/models/batch_payload.dart';
import 'package:openpanel_flutter/src/models/open_panel_options.dart';
import 'package:openpanel_flutter/src/services/openpanel_http_client.dart';

import '../helpers/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockDio mockDio;
  late OpenpanelHttpClient client;
  final logger = silentLogger();

  setUp(() {
    mockDio = MockDio();
    client = OpenpanelHttpClient.withDio(mockDio, logger: logger);
    when(() => mockDio.interceptors).thenReturn(Interceptors());
  });

  // -------------------------------------------------------------------------
  // init()
  // -------------------------------------------------------------------------
  group('init', () {
    test('completes with default options', () async {
      final freshClient = OpenpanelHttpClient(verbose: false, logger: logger);

      await freshClient.init(OpenpanelOptions(clientId: 'client-1'));
    });

    test('completes with verbose logging and a client secret', () async {
      final freshClient = OpenpanelHttpClient(verbose: true, logger: logger);

      await freshClient.init(OpenpanelOptions(
        clientId: 'client-1',
        clientSecret: 'secret-1',
        verbose: true,
      ));
    });
  });

  // -------------------------------------------------------------------------
  // increment() / decrement()
  // -------------------------------------------------------------------------
  group('increment / decrement', () {
    setUp(() {
      when(() => mockDio.post<dynamic>(
            '/track',
            data: any(named: 'data'),
          )).thenAnswer((_) async => mockResponse<dynamic>(statusCode: 200));
    });

    test('increment posts /track with type=increment', () async {
      client.increment(profileId: 'u1', property: 'visits', value: 2);

      // Give the fire-and-forget a tick to run
      await Future<void>.delayed(Duration.zero);

      final captured = verify(() => mockDio.post<dynamic>(
            '/track',
            data: captureAny(named: 'data'),
          )).captured;

      final body = captured.first as Map<String, dynamic>;
      expect(body['type'], 'increment');
      expect(body['payload'], {
        'profileId': 'u1',
        'property': 'visits',
        'value': 2,
      });
    });

    test('decrement posts /track with type=decrement', () async {
      client.decrement(profileId: 'u1', property: 'credits', value: 1);

      await Future<void>.delayed(Duration.zero);

      final captured = verify(() => mockDio.post<dynamic>(
            '/track',
            data: captureAny(named: 'data'),
          )).captured;

      final body = captured.first as Map<String, dynamic>;
      expect(body['type'], 'decrement');
      expect(body['payload'], {
        'profileId': 'u1',
        'property': 'credits',
        'value': 1,
      });
    });
  });

  // -------------------------------------------------------------------------
  // batch() — SocketException path
  // -------------------------------------------------------------------------
  group('batch transport errors', () {
    test('SocketException → BatchTransportError with isTransient=true',
        () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/track',
            data: any(named: 'data'),
          )).thenThrow(const SocketException('Network unreachable'));

      expect(
        () => client.batch([
          const BatchedEvent(type: 'track', payload: {'name': 'e'}),
        ]),
        throwsA(isA<BatchTransportError>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.isTransient, 'isTransient', isTrue)),
      );
    });

    test('DioException(unknown) wrapping SocketException → isTransient=true',
        () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/track',
            data: any(named: 'data'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/track'),
        error: const SocketException('Connection reset'),
        type: DioExceptionType.unknown,
      ));

      expect(
        () => client.batch([
          const BatchedEvent(type: 'track', payload: {'name': 'e'}),
        ]),
        throwsA(isA<BatchTransportError>()
            .having((e) => e.isTransient, 'isTransient', isTrue)),
      );
    });

    test('DioException(cancel) → isTransient=false', () async {
      when(() => mockDio.post<Map<String, dynamic>>(
            '/track',
            data: any(named: 'data'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/track'),
        type: DioExceptionType.cancel,
      ));

      expect(
        () => client.batch([
          const BatchedEvent(type: 'track', payload: {'name': 'e'}),
        ]),
        throwsA(isA<BatchTransportError>()
            .having((e) => e.isTransient, 'isTransient', isFalse)),
      );
    });
  });

  // -------------------------------------------------------------------------
  // runApiCall() — error handling
  // -------------------------------------------------------------------------
  group('runApiCall', () {
    test('returns error tuple on DioException', () async {
      final result = await client.runApiCall(() async {
        throw DioException(
          requestOptions: RequestOptions(path: '/track'),
          message: 'Bad Request',
          type: DioExceptionType.badResponse,
        );
      });

      expect(result.response, isNull);
      expect(result.error, isA<DioException>());
    });

    test('returns error tuple on SocketException (verbose logging)', () async {
      // Default constructor with verbose=true so _logError exercises the
      // logging branch. runApiCall never touches _dio, so no init() needed.
      final verboseClient = OpenpanelHttpClient(verbose: true, logger: logger);

      final result = await verboseClient.runApiCall(() async {
        throw const SocketException('Network unreachable');
      });

      expect(result.response, isNull);
      expect(result.error, isA<SocketException>());
    });
  });
}
