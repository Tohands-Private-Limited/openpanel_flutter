import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:logger/logger.dart';
import 'package:meta/meta.dart';
import 'package:openpanel_flutter/openpanel_flutter.dart';
import 'package:openpanel_flutter/src/constants/constants.dart';
import 'package:openpanel_flutter/src/models/batch_payload.dart';
import 'package:openpanel_flutter/src/models/post_event_payload.dart';

import 'device_user_agent.dart';

typedef ApiResponse<T, E> = ({T? response, E? error});

class OpenpanelHttpClient {
  late final Dio _dio;
  final bool verbose;
  final Logger _logger;

  OpenpanelHttpClient({
    required this.verbose,
    required Logger logger,
  }) : _logger = logger;

  /// Constructor for testing — injects a pre-configured [Dio] instance so
  /// tests can stub HTTP calls without going through [init].
  @visibleForTesting
  OpenpanelHttpClient.withDio(Dio dio, {required Logger logger})
      : _dio = dio,
        verbose = false,
        _logger = logger;

  Future<void> init(OpenpanelOptions options) async {
    _dio = Dio(
      BaseOptions(
        baseUrl: options.url ?? kDefaultBaseUrl,
        headers: {
          'openpanel-client-id': options.clientId,
          'openpanel-sdk-name': 'openpanel-flutter',
          'openpanel-sdk-version': '0.4.0',
          if (options.clientSecret != null)
            'openpanel-client-secret': options.clientSecret,
          'User-Agent': await DeviceUserAgent().getUserAgent(),
        },
      ),
    );
    _dio.interceptors.add(RetryInterceptor(dio: _dio));
    if (options.verbose) {
      _dio.interceptors
          .add(LogInterceptor(requestBody: true, responseBody: true));
    }
  }

  void updateProfile({
    required UpdateProfilePayload payload,
    required Map<String, dynamic> stateProperties,
  }) {
    runApiCall(() async {
      await _dio.post('/track', data: {
        'type': 'identify',
        'payload': {
          ...payload.toJson(),
          'properties': {
            ...payload.properties,
            ...stateProperties,
          }
        }
      });
    });
  }

  void increment({
    required String profileId,
    required String property,
    required int value,
  }) {
    runApiCall(() async {
      _dio.post('/track', data: {
        'type': 'increment',
        'payload': {
          'profileId': profileId,
          'property': property,
          'value': value,
        }
      });
    });
  }

  void decrement({
    required String profileId,
    required String property,
    required int value,
  }) {
    runApiCall(() async {
      _dio.post('/track', data: {
        'type': 'decrement',
        'payload': {
          'profileId': profileId,
          'property': property,
          'value': value,
        }
      });
    });
  }

  Future<String?> event({required PostEventPayload payload}) async {
    final response = await runApiCall(() async {
      final response = await _dio.post('/track', data: {
        'type': 'track',
        'payload': payload.toJson(),
      });
      return response.data as String;
    });

    if (response.error != null) {
      return null;
    }

    return response.response;
  }

  Future<BatchResponse> batch(List<BatchedEvent> events) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/track/batch',
        data: {'events': events.map((e) => e.toJson()).toList()},
      );
      return BatchResponse.fromJson(response.data!);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      throw BatchTransportError(
        e.message ?? e.toString(),
        statusCode: statusCode,
        isTransient: _isTransientDioFailure(e),
      );
    } on SocketException catch (e) {
      throw BatchTransportError(e.message, isTransient: true);
    }
  }

  /// Returns true when a [DioException] represents a failure that is NOT the
  /// event's fault — the server or network never accepted the payload, so
  /// retrying the same batch can succeed without any changes.
  ///
  /// Bundling 5xx with connect failures: both indicate the server couldn't
  /// process the request through no fault of the event data; the server will
  /// likely recover, and the same payload should be retried as-is.
  bool _isTransientDioFailure(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        return code >= 500 && code < 600;
      case DioExceptionType.unknown:
        return e.error is SocketException;
      default:
        return false;
    }
  }

  Future<ApiResponse> runApiCall<T, E>(Future<T> Function() apiCall) async {
    try {
      final response = await apiCall();

      return (response: response, error: null);
    } on DioException catch (e) {
      _logger.e(e.message);
      return (response: null, error: e);
    } on SocketException catch (e) {
      _logError('Failed to connect to the internet.');
      return (response: null, error: e);
    }
  }

  void _logError(String message) {
    if (verbose) {
      _logger.e(message);
    }
  }
}
