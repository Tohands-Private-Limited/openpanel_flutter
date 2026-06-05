import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Shared test helpers
// ---------------------------------------------------------------------------

/// Logger output that silently discards all lines.
class SilentOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

/// A [Logger] that swallows everything — keeps test output clean.
Logger silentLogger() => Logger(output: SilentOutput(), level: Level.off);

class MockDio extends Mock implements Dio {}

/// Build a fake [Response] that Dio would return from a `/track` call.
Response<T> mockResponse<T>({required int statusCode, T? data}) {
  return Response<T>(
    requestOptions: RequestOptions(path: '/track'),
    statusCode: statusCode,
    data: data,
  );
}
