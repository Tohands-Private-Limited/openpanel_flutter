import 'dart:convert';

import 'package:logger/logger.dart';
import 'package:openpanel_flutter/src/models/batch_payload.dart';
import 'package:openpanel_flutter/src/services/event_queue.dart';

/// Performs a single drain pass: pulls pending events, sends them as a batch,
/// and updates the queue rows based on the server response.
///
/// Extracted from [Openpanel] so that the logic can be unit-tested without the
/// singleton/Flutter binding.
class BatchDrainer {
  final EventQueue _queue;
  final Future<BatchResponse> Function(List<BatchedEvent>) _batchFn;
  final int _maxBatchSize;
  final Logger? _logger;

  /// Optional callback invoked with every successful [BatchResponse].
  /// Useful for debug listeners (e.g. the debug screen).
  final void Function(BatchResponse)? onResponse;

  BatchDrainer({
    required EventQueue queue,
    required Future<BatchResponse> Function(List<BatchedEvent>) batchFn,
    required int maxBatchSize,
    Logger? logger,
    this.onResponse,
  })  : _queue = queue,
        _batchFn = batchFn,
        _maxBatchSize = maxBatchSize,
        _logger = logger;

  /// Performs one drain pass.
  ///
  /// - Fetches up to [_maxBatchSize] pending events.
  /// - Sends them via [_batchFn].
  /// - Marks accepted (and validation-rejected) rows as sent (deleted).
  /// - Marks internal-rejected rows as failed (retry counter ticks).
  /// - On [BatchTransportError]: marks ALL rows as failed (whole batch retry).
  /// - On any other exception: logs it and marks ALL rows as failed so the
  ///   retry counter ticks and "poisoned" batches are eventually dropped.
  Future<void> drainOnce() async {
    final batch = await _queue.pending(limit: _maxBatchSize);
    if (batch.isEmpty) return;

    final events = batch
        .map((row) => BatchedEvent(
              type: row.type,
              payload:
                  Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
            ))
        .toList();
    final allIds = batch.map((r) => r.id).toList();

    try {
      final response = await _batchFn(events);

      // Notify optional response listener (e.g. debug screen).
      onResponse?.call(response);

      final rejectedIndices = <int>{};
      for (final rejection in response.rejected) {
        // Guard against a server returning an out-of-range index (server bug).
        if (rejection.index < 0 || rejection.index >= allIds.length) {
          _logger?.w(
            'BatchDrainer: server returned out-of-range rejection index '
            '${rejection.index} (batch size ${allIds.length}) — skipping.',
          );
          continue;
        }
        rejectedIndices.add(rejection.index);
      }

      // Delete accepted events (all non-rejected).
      final successIds = <int>[];
      for (var i = 0; i < allIds.length; i++) {
        if (!rejectedIndices.contains(i)) {
          successIds.add(allIds[i]);
        }
      }
      await _queue.markSent(successIds);

      // Validation failures will never succeed on retry — drop them.
      final validationIds = <int>[];
      final internalIds = <int>[];
      for (final r in response.rejected) {
        if (r.index < 0 || r.index >= allIds.length) continue; // already warned above
        if (r.reason == 'validation') {
          validationIds.add(allIds[r.index]);
        } else {
          internalIds.add(allIds[r.index]);
        }
      }

      if (validationIds.isNotEmpty) {
        _logger?.w(
          'BatchDrainer: dropping ${validationIds.length} event(s) rejected '
          'due to validation errors (will not be retried).',
        );
        await _queue.markSent(validationIds);
      }
      if (internalIds.isNotEmpty) {
        await _queue.markFailed(internalIds, 'server internal error');
      }
    } on BatchTransportError catch (e) {
      _logger?.e('BatchDrainer: transport error — $e');
      await _queue.markFailed(allIds, e.toString());
    } on Exception catch (e, st) {
      // Unexpected error (RangeError, TypeError, null deref from a malformed
      // response, …). Tick the retry counter so poisoned batches are eventually
      // dropped rather than replayed forever.
      _logger?.e(
        'BatchDrainer: unexpected error during drain',
        error: e,
        stackTrace: st,
      );
      await _queue.markFailed(allIds, 'unexpected: $e');
    }
  }
}
