import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:logger/logger.dart';
import 'package:openpanel_flutter/src/services/database/event_queue_database.dart';

class EventQueue {
  final EventQueueDatabase _db;
  final int _maxRetries;
  final Logger? _logger;

  EventQueue(this._db, {required int maxRetries, Logger? logger})
      : _maxRetries = maxRetries,
        _logger = logger;

  Future<void> enqueue({
    required String type,
    required Map<String, dynamic> payload,
    required DateTime occurredAt,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.pendingEvents).insert(PendingEventsCompanion.insert(
          type: type,
          payloadJson: jsonEncode(payload),
          occurredAtMs: occurredAt.millisecondsSinceEpoch,
          createdAtMs: nowMs,
        ));
  }

  Future<List<PendingEventRow>> pending({required int limit}) async {
    return (_db.select(_db.pendingEvents)
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(limit))
        .get();
  }

  Future<int> count() async {
    final countExpr = _db.pendingEvents.id.count();
    final query = _db.selectOnly(_db.pendingEvents)..addColumns([countExpr]);
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }

  Future<void> markSent(List<int> ids) async {
    if (ids.isEmpty) return;
    await (_db.delete(_db.pendingEvents)
          ..where((t) => t.id.isIn(ids)))
        .go();
  }

  Future<void> markFailed(List<int> ids, String error) async {
    if (ids.isEmpty) return;
    await _db.transaction(() async {
      for (final id in ids) {
        final rows = await (_db.select(_db.pendingEvents)
              ..where((t) => t.id.equals(id)))
            .get();
        if (rows.isEmpty) continue;
        final row = rows.first;
        final newCount = row.retryCount + 1;
        if (newCount >= _maxRetries) {
          // Drop permanently — retrying a broken event forever wastes bandwidth and queue space.
          _logger?.w('Dropping event id=$id after $newCount failures: $error');
          await (_db.delete(_db.pendingEvents)
                ..where((t) => t.id.equals(id)))
              .go();
        } else {
          await (_db.update(_db.pendingEvents)
                ..where((t) => t.id.equals(id)))
              .write(PendingEventsCompanion(
                retryCount: Value(newCount),
                lastError: Value(error),
              ));
        }
      }
    });
  }

  Future<void> deleteAll() async {
    await _db.delete(_db.pendingEvents).go();
  }

  Future<void> close() => _db.close();
}
