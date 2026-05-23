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

class BatchTransportError implements Exception {
  final String message;
  final int? statusCode;

  const BatchTransportError(this.message, {this.statusCode});

  @override
  String toString() => 'BatchTransportError($statusCode): $message';
}
