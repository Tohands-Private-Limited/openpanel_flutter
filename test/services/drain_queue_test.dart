import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:openpanel_flutter/src/models/batch_payload.dart';
import 'package:openpanel_flutter/src/services/batch_drainer.dart';
import 'package:openpanel_flutter/src/services/database/event_queue_database.dart';
import 'package:openpanel_flutter/src/services/event_queue.dart';

// ---------------------------------------------------------------------------
// Helpers / silence logger
// ---------------------------------------------------------------------------

class _SilentOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

Logger _silentLogger() =>
    Logger(output: _SilentOutput(), level: Level.off);

EventQueueDatabase _freshDb() => EventQueueDatabase(NativeDatabase.memory());

/// Enqueues [n] dummy track events and returns their row ids.
Future<List<int>> _insertEvents(EventQueue queue, int n) async {
  for (var i = 0; i < n; i++) {
    await queue.enqueue(
      type: 'track',
      payload: {'seq': i},
      occurredAt: DateTime.now(),
    );
  }
  final rows = await queue.pending(limit: n + 10);
  return rows.map((r) => r.id).toList();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late EventQueueDatabase db;
  late EventQueue queue;

  setUp(() {
    db = _freshDb();
    queue = EventQueue(db, maxRetries: 3, logger: _silentLogger());
  });

  tearDown(() async {
    await db.close();
  });

  BatchDrainer makeDrainer(
    Future<BatchResponse> Function(List<BatchedEvent>) batchFn, {
    int maxBatchSize = 50,
  }) =>
      BatchDrainer(
        queue: queue,
        batchFn: batchFn,
        maxBatchSize: maxBatchSize,
        logger: _silentLogger(),
      );

  // -------------------------------------------------------------------------
  // Empty queue — no batchFn call
  // -------------------------------------------------------------------------
  test('empty queue — batchFn is never called', () async {
    var called = false;
    final drainer = makeDrainer((_) async {
      called = true;
      return const BatchResponse(accepted: 0, rejected: []);
    });
    await drainer.drainOnce();
    expect(called, isFalse);
    expect(await queue.count(), 0);
  });

  // -------------------------------------------------------------------------
  // All events accepted
  // -------------------------------------------------------------------------
  test('all events accepted — all rows deleted', () async {
    await _insertEvents(queue, 3);

    final drainer = makeDrainer(
      (events) async => BatchResponse(accepted: events.length, rejected: []),
    );
    await drainer.drainOnce();
    expect(await queue.count(), 0);
  });

  // -------------------------------------------------------------------------
  // Mixed: some validation-rejected (dropped), some accepted
  // -------------------------------------------------------------------------
  test('validation-rejected events are dropped (not retried)', () async {
    await _insertEvents(queue, 3);

    // Event at index 1 is validation-rejected; events 0 and 2 are accepted.
    final drainer = makeDrainer((events) async => BatchResponse(
          accepted: 2,
          rejected: [
            const BatchRejection(
                index: 1, reason: 'validation', error: 'bad field'),
          ],
        ));
    await drainer.drainOnce();
    // All three should be deleted (accepted 0,2 + dropped validation 1).
    expect(await queue.count(), 0);
  });

  // -------------------------------------------------------------------------
  // Mixed: some internal-rejected (retried), some accepted
  // -------------------------------------------------------------------------
  test('internal-rejected events increment retry counter, accepted are deleted',
      () async {
    await _insertEvents(queue, 3);
    final allRows = await queue.pending(limit: 10);

    // Event at index 2 is internal-rejected (server error, retry).
    final drainer = makeDrainer((events) async => BatchResponse(
          accepted: 2,
          rejected: [
            const BatchRejection(
                index: 2, reason: 'internal', error: 'server oops'),
          ],
        ));
    await drainer.drainOnce();

    // Rows 0 and 1 should be gone; row 2 should still exist with retryCount=1.
    expect(await queue.count(), 1);
    final remaining = await queue.pending(limit: 10);
    expect(remaining.first.id, allRows[2].id);
    expect(remaining.first.retryCount, 1);
  });

  // -------------------------------------------------------------------------
  // All internal-rejected
  // -------------------------------------------------------------------------
  test('all internal-rejected — all rows get retryCount incremented', () async {
    await _insertEvents(queue, 2);

    final drainer = makeDrainer((events) async => BatchResponse(
          accepted: 0,
          rejected: [
            const BatchRejection(
                index: 0, reason: 'internal', error: 'err'),
            const BatchRejection(
                index: 1, reason: 'internal', error: 'err'),
          ],
        ));
    await drainer.drainOnce();

    expect(await queue.count(), 2);
    final rows = await queue.pending(limit: 10);
    for (final r in rows) {
      expect(r.retryCount, 1);
    }
  });

  // -------------------------------------------------------------------------
  // BatchTransportError — all rows retried
  // -------------------------------------------------------------------------
  test('BatchTransportError — all rows incremented (whole batch retry)',
      () async {
    await _insertEvents(queue, 3);

    final drainer = makeDrainer((_) async =>
        throw const BatchTransportError('network timeout', statusCode: 503));
    await drainer.drainOnce();

    expect(await queue.count(), 3);
    final rows = await queue.pending(limit: 10);
    for (final r in rows) {
      expect(r.retryCount, 1);
    }
  });

  // -------------------------------------------------------------------------
  // Unexpected exception — all rows incremented (no permanent poison)
  // -------------------------------------------------------------------------
  test('unexpected exception — all rows incremented so poison batch is eventually dropped',
      () async {
    await _insertEvents(queue, 2);

    final drainer = makeDrainer((_) async {
      throw Exception('something weird happened');
    });
    await drainer.drainOnce();

    expect(await queue.count(), 2);
    final rows = await queue.pending(limit: 10);
    for (final r in rows) {
      expect(r.retryCount, 1);
    }
  });

  // -------------------------------------------------------------------------
  // Unexpected exception exhausts retries — events eventually dropped
  // -------------------------------------------------------------------------
  test('repeated unexpected exceptions exhaust retries and drop events',
      () async {
    // maxRetries=3
    await _insertEvents(queue, 1);

    final drainer = makeDrainer((_) async => throw Exception('boom'));

    // 3 drain passes → retryCount hits maxRetries → row dropped.
    for (var i = 0; i < 3; i++) {
      await drainer.drainOnce();
    }

    expect(await queue.count(), 0);
  });

  // -------------------------------------------------------------------------
  // Out-of-range rejection index — skipped, other rows handled correctly
  // -------------------------------------------------------------------------
  test('out-of-range rejection index is skipped, in-range entries are handled',
      () async {
    await _insertEvents(queue, 2);
    final allRows = await queue.pending(limit: 10);

    // Index 99 is out of range; index 0 is internal-rejected.
    final drainer = makeDrainer((events) async => BatchResponse(
          accepted: 1,
          rejected: [
            const BatchRejection(
                index: 99, reason: 'internal', error: 'oob bug'), // server bug
            const BatchRejection(
                index: 0, reason: 'internal', error: 'err'),
          ],
        ));
    await drainer.drainOnce();

    // Row at index 1 was accepted → deleted.
    // Row at index 0 was internal-rejected → retryCount=1.
    // OOB rejection at 99 was silently skipped.
    expect(await queue.count(), 1);
    final remaining = await queue.pending(limit: 10);
    expect(remaining.first.id, allRows[0].id);
    expect(remaining.first.retryCount, 1);
  });

  // -------------------------------------------------------------------------
  // onResponse callback is invoked on success
  // -------------------------------------------------------------------------
  test('onResponse callback is called with the BatchResponse on success',
      () async {
    await _insertEvents(queue, 1);

    BatchResponse? captured;
    final drainer = BatchDrainer(
      queue: queue,
      batchFn: (events) async =>
          const BatchResponse(accepted: 1, rejected: []),
      maxBatchSize: 50,
      logger: _silentLogger(),
      onResponse: (r) => captured = r,
    );
    await drainer.drainOnce();

    expect(captured, isNotNull);
    expect(captured!.accepted, 1);
    expect(captured!.rejected, isEmpty);
  });

  // -------------------------------------------------------------------------
  // maxBatchSize is respected
  // -------------------------------------------------------------------------
  test('drainOnce fetches at most maxBatchSize events per pass', () async {
    await _insertEvents(queue, 5);

    int sentCount = 0;
    final drainer = makeDrainer(
      (events) async {
        sentCount = events.length;
        return BatchResponse(accepted: events.length, rejected: []);
      },
      maxBatchSize: 3,
    );
    await drainer.drainOnce();

    expect(sentCount, 3);
    // 2 events remain (not yet drained).
    expect(await queue.count(), 2);
  });
}
