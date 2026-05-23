import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'event_queue_database.g.dart';

@DataClassName('PendingEventRow')
class PendingEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text()();
  TextColumn get payloadJson => text()();
  IntColumn get occurredAtMs => integer()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  IntColumn get createdAtMs => integer()();
}

@DriftDatabase(tables: [PendingEvents])
class EventQueueDatabase extends _$EventQueueDatabase {
  EventQueueDatabase(super.e);

  factory EventQueueDatabase.open() =>
      EventQueueDatabase(driftDatabase(name: 'openpanel_event_queue'));

  @override
  int get schemaVersion => 1;
}
