import 'package:equatable/equatable.dart';

class BatchedEvent extends Equatable {
  final String type;
  final Map<String, dynamic> payload;

  const BatchedEvent({required this.type, required this.payload});

  Map<String, dynamic> toJson() => {'type': type, 'payload': payload};

  @override
  List<Object?> get props => [type, payload];
}

class BatchRejection extends Equatable {
  final int index;
  final String reason;
  final String error;

  const BatchRejection({
    required this.index,
    required this.reason,
    required this.error,
  });

  factory BatchRejection.fromJson(Map<String, dynamic> json) => BatchRejection(
        index: json['index'] as int,
        reason: json['reason'] as String,
        error: json['error'] as String,
      );

  @override
  List<Object?> get props => [index, reason, error];
}

class BatchResponse extends Equatable {
  final int accepted;
  final List<BatchRejection> rejected;

  const BatchResponse({required this.accepted, required this.rejected});

  factory BatchResponse.fromJson(Map<String, dynamic> json) => BatchResponse(
        accepted: json['accepted'] as int,
        rejected: (json['rejected'] as List<dynamic>? ?? [])
            .map((e) => BatchRejection.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props => [accepted, rejected];
}

/// Thrown by [OpenpanelHttpClient.batch] when the batch cannot be delivered.
///
/// [isTransient] distinguishes two failure modes:
///   - `true` — the request never reached an accepting server (connection
///     error, timeout, DNS failure, server 5xx). The payload is intact and will
///     succeed on retry; do NOT increment the event retry counter.
///   - `false` — the server actively processed (or rejected) the request
///     (HTTP 4xx). Retrying the same payload will not help; the retry counter
///     SHOULD be incremented so the event is eventually dropped.
class BatchTransportError implements Exception {
  final String message;
  final int? statusCode;

  /// Whether this failure is transient (offline / server 5xx).
  /// Transient failures should not count against the event retry budget.
  final bool isTransient;

  const BatchTransportError(
    this.message, {
    this.statusCode,
    this.isTransient = false,
  });

  @override
  String toString() => 'BatchTransportError($statusCode, transient=$isTransient): $message';
}
