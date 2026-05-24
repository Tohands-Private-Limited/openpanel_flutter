import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openpanel_flutter/src/services/database/event_queue_database.dart';
import 'package:openpanel_flutter/src/services/event_queue.dart';

EventQueueDatabase _freshDb() => EventQueueDatabase(NativeDatabase.memory());

void main() {
  group('EventQueue', () {
    late EventQueueDatabase db;
    late EventQueue queue;

    setUp(() {
      db = _freshDb();
      queue = EventQueue(db, maxRetries: 5);
    });

    tearDown(() async {
      await db.close();
    });

    // -------------------------------------------------------------------------
    // enqueue
    // -------------------------------------------------------------------------
    group('enqueue', () {
      test('inserts a row with correct type, payloadJson, and occurredAtMs',
          () async {
        final occurredAt = DateTime(2024, 1, 15, 12, 0, 0).toUtc();
        await queue.enqueue(
          type: 'track',
          payload: {'name': 'page_view', 'count': 1},
          occurredAt: occurredAt,
        );

        final rows = await queue.pending(limit: 10);
        expect(rows.length, 1);
        expect(rows.first.type, 'track');
        expect(
          jsonDecode(rows.first.payloadJson),
          {'name': 'page_view', 'count': 1},
        );
        expect(rows.first.occurredAtMs, occurredAt.millisecondsSinceEpoch);
      });

      test('newly inserted row starts with retryCount 0 and no lastError',
          () async {
        await queue.enqueue(
          type: 'identify',
          payload: {'profileId': 'abc'},
          occurredAt: DateTime.now(),
        );

        final rows = await queue.pending(limit: 10);
        expect(rows.first.retryCount, 0);
        expect(rows.first.lastError, isNull);
      });
    });

    // -------------------------------------------------------------------------
    // pending
    // -------------------------------------------------------------------------
    group('pending', () {
      test('returns rows in ascending id order', () async {
        await queue.enqueue(
            type: 'track', payload: {'seq': 1}, occurredAt: DateTime.now());
        await queue.enqueue(
            type: 'track', payload: {'seq': 2}, occurredAt: DateTime.now());
        await queue.enqueue(
            type: 'track', payload: {'seq': 3}, occurredAt: DateTime.now());

        final rows = await queue.pending(limit: 10);
        final seqs = rows
            .map((r) => (jsonDecode(r.payloadJson) as Map)['seq'] as int)
            .toList();
        expect(seqs, [1, 2, 3]);
      });

      test('respects the limit parameter', () async {
        for (var i = 0; i < 5; i++) {
          await queue.enqueue(
              type: 'track', payload: {'i': i}, occurredAt: DateTime.now());
        }

        final rows = await queue.pending(limit: 3);
        expect(rows.length, 3);
      });

      test('returns empty list when queue is empty', () async {
        final rows = await queue.pending(limit: 10);
        expect(rows, isEmpty);
      });
    });

    // -------------------------------------------------------------------------
    // count
    // -------------------------------------------------------------------------
    group('count', () {
      test('returns 0 for empty queue', () async {
        expect(await queue.count(), 0);
      });

      test('returns the correct number after inserts', () async {
        await queue.enqueue(
            type: 'track', payload: {}, occurredAt: DateTime.now());
        await queue.enqueue(
            type: 'identify', payload: {}, occurredAt: DateTime.now());
        expect(await queue.count(), 2);
      });
    });

    // -------------------------------------------------------------------------
    // markSent
    // -------------------------------------------------------------------------
    group('markSent', () {
      test('deletes the specified row', () async {
        await queue.enqueue(
            type: 'track', payload: {}, occurredAt: DateTime.now());
        final row = (await queue.pending(limit: 1)).first;

        await queue.markSent([row.id]);

        expect(await queue.count(), 0);
      });

      test('only deletes targeted ids — leaves others intact', () async {
        await queue.enqueue(
            type: 'track', payload: {'n': 1}, occurredAt: DateTime.now());
        await queue.enqueue(
            type: 'track', payload: {'n': 2}, occurredAt: DateTime.now());
        final rows = await queue.pending(limit: 10);
        final idToDelete = rows.first.id;

        await queue.markSent([idToDelete]);

        final remaining = await queue.pending(limit: 10);
        expect(remaining.length, 1);
        expect(remaining.first.id, isNot(idToDelete));
      });

      test('is a no-op when called with an empty list', () async {
        await queue.enqueue(
            type: 'track', payload: {}, occurredAt: DateTime.now());
        await expectLater(queue.markSent([]), completes);
        expect(await queue.count(), 1);
      });
    });

    // -------------------------------------------------------------------------
    // markFailed
    // -------------------------------------------------------------------------
    group('markFailed', () {
      test('increments retryCount and sets lastError on first failure',
          () async {
        await queue.enqueue(
            type: 'track', payload: {}, occurredAt: DateTime.now());
        final row = (await queue.pending(limit: 1)).first;

        await queue.markFailed([row.id], 'network error');

        final updated = (await queue.pending(limit: 1)).first;
        expect(updated.retryCount, 1);
        expect(updated.lastError, 'network error');
      });

      test('increments retryCount on each successive failure below maxRetries',
          () async {
        const maxRetries = 5;
        final q = EventQueue(db, maxRetries: maxRetries);
        await q.enqueue(
            type: 'track', payload: {}, occurredAt: DateTime.now());
        final id = (await q.pending(limit: 1)).first.id;

        // Call markFailed maxRetries-1 times — row must survive
        for (var i = 1; i < maxRetries; i++) {
          await q.markFailed([id], 'err $i');
          final row = (await q.pending(limit: 1)).first;
          expect(row.retryCount, i);
        }
        expect(await q.count(), 1);
      });

      test('drops the row when retry count reaches maxRetries', () async {
        const maxRetries = 5;
        final q = EventQueue(db, maxRetries: maxRetries);
        await q.enqueue(
            type: 'track', payload: {}, occurredAt: DateTime.now());
        final id = (await q.pending(limit: 1)).first.id;

        // Call markFailed exactly maxRetries times — last call should delete
        for (var i = 0; i < maxRetries; i++) {
          await q.markFailed([id], 'err');
        }

        expect(await q.count(), 0);
      });

      test(
          'handles a mixed batch: some ids drop, some just increment',
          () async {
        // Insert two events
        await queue.enqueue(
            type: 'track', payload: {'n': 1}, occurredAt: DateTime.now());
        await queue.enqueue(
            type: 'track', payload: {'n': 2}, occurredAt: DateTime.now());
        final rows = await queue.pending(limit: 10);
        final idA = rows[0].id;
        final idB = rows[1].id;

        // Exhaust retries for idA (4 previous fails, 1 more → drops)
        for (var i = 0; i < 4; i++) {
          await queue.markFailed([idA], 'err');
        }

        // Now call markFailed on both — idA should drop, idB should increment
        await queue.markFailed([idA, idB], 'err');

        final remaining = await queue.pending(limit: 10);
        expect(remaining.length, 1);
        expect(remaining.first.id, idB);
        expect(remaining.first.retryCount, 1);
      });

      test('is a no-op when called with an empty list', () async {
        await queue.enqueue(
            type: 'track', payload: {}, occurredAt: DateTime.now());
        await expectLater(queue.markFailed([], 'x'), completes);
        expect(await queue.count(), 1);
      });
    });

    // -------------------------------------------------------------------------
    // purgeOlderThan
    // -------------------------------------------------------------------------
    group('purgeOlderThan', () {
      test('deletes only rows older than cutoff; returns correct count',
          () async {
        final old = DateTime.now().subtract(const Duration(days: 7));
        final fresh = DateTime.now();

        // Insert 2 old events and 1 fresh event via the queue enqueue,
        // then overwrite createdAtMs directly via the DB for the old rows.
        await queue.enqueue(
            type: 'track', payload: {'n': 1}, occurredAt: old);
        await queue.enqueue(
            type: 'track', payload: {'n': 2}, occurredAt: old);
        await queue.enqueue(
            type: 'track', payload: {'n': 3}, occurredAt: fresh);

        // Backdate createdAtMs for the first two rows.
        final allRows = await queue.pending(limit: 10);
        final oldMs = old.millisecondsSinceEpoch;
        for (final row in allRows.take(2)) {
          await (db.update(db.pendingEvents)
                ..where((t) => t.id.equals(row.id)))
              .write(PendingEventsCompanion(
                  createdAtMs: drift.Value(oldMs)));
        }

        final cutoff = DateTime.now().subtract(const Duration(days: 5));
        final purged = await queue.purgeOlderThan(cutoff);

        expect(purged, 2);
        expect(await queue.count(), 1);
        final remaining = await queue.pending(limit: 10);
        expect((jsonDecode(remaining.first.payloadJson) as Map)['n'], 3);
      });

      test('purgeOlderThan with no expired rows returns 0 and does not error',
          () async {
        await queue.enqueue(
            type: 'track', payload: {}, occurredAt: DateTime.now());

        final cutoff = DateTime.now().subtract(const Duration(days: 5));
        final purged = await queue.purgeOlderThan(cutoff);

        expect(purged, 0);
        expect(await queue.count(), 1);
      });

      test('purgeOlderThan with all rows expired empties the queue', () async {
        final old = DateTime.now().subtract(const Duration(days: 7));
        await queue.enqueue(
            type: 'track', payload: {'n': 1}, occurredAt: old);
        await queue.enqueue(
            type: 'track', payload: {'n': 2}, occurredAt: old);

        // Backdate createdAtMs for all rows.
        final allRows = await queue.pending(limit: 10);
        final oldMs = old.millisecondsSinceEpoch;
        for (final row in allRows) {
          await (db.update(db.pendingEvents)
                ..where((t) => t.id.equals(row.id)))
              .write(PendingEventsCompanion(
                  createdAtMs: drift.Value(oldMs)));
        }

        final cutoff = DateTime.now().subtract(const Duration(days: 5));
        final purged = await queue.purgeOlderThan(cutoff);

        expect(purged, 2);
        expect(await queue.count(), 0);
      });
    });

    // -------------------------------------------------------------------------
    // deleteAll
    // -------------------------------------------------------------------------
    group('deleteAll', () {
      test('removes all rows from the queue', () async {
        await queue.enqueue(
            type: 'track', payload: {}, occurredAt: DateTime.now());
        await queue.enqueue(
            type: 'identify', payload: {}, occurredAt: DateTime.now());

        await queue.deleteAll();

        expect(await queue.count(), 0);
      });

      test('succeeds on an already-empty queue', () async {
        await expectLater(queue.deleteAll(), completes);
      });
    });
  });
}
