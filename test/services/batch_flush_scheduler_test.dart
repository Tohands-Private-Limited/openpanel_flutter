import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openpanel_flutter/src/services/batch_flush_scheduler.dart';

void main() {
  group('BatchFlushScheduler', () {
    const interval = Duration(seconds: 30);
    const sizeThreshold = 10;

    // -----------------------------------------------------------------------
    // Timer-based triggering
    // -----------------------------------------------------------------------
    group('periodic timer', () {
      test('start() + elapsing one interval triggers onFlush exactly once',
          () {
        fakeAsync((async) {
          var flushCount = 0;
          final scheduler = BatchFlushScheduler(
            interval: interval,
            sizeThreshold: sizeThreshold,
            onFlush: () async => flushCount++,
            pendingCountProvider: () async => 0,
          );

          scheduler.start();
          async.elapse(interval);
          async.flushMicrotasks();

          expect(flushCount, 1);
          scheduler.stop();
        });
      });

      test('start() + elapsing two intervals triggers onFlush twice', () {
        fakeAsync((async) {
          var flushCount = 0;
          final scheduler = BatchFlushScheduler(
            interval: interval,
            sizeThreshold: sizeThreshold,
            onFlush: () async => flushCount++,
            pendingCountProvider: () async => 0,
          );

          scheduler.start();
          async.elapse(interval * 2);
          async.flushMicrotasks();

          expect(flushCount, 2);
          scheduler.stop();
        });
      });

      test('stop() cancels the timer; no more flushes happen', () {
        fakeAsync((async) {
          var flushCount = 0;
          final scheduler = BatchFlushScheduler(
            interval: interval,
            sizeThreshold: sizeThreshold,
            onFlush: () async => flushCount++,
            pendingCountProvider: () async => 0,
          );

          scheduler.start();
          async.elapse(interval); // one flush
          async.flushMicrotasks();
          expect(flushCount, 1);

          scheduler.stop();
          async.elapse(interval * 3); // timer is dead
          async.flushMicrotasks();

          expect(flushCount, 1); // no additional flushes
        });
      });
    });

    // -----------------------------------------------------------------------
    // flushNow
    // -----------------------------------------------------------------------
    group('flushNow', () {
      test('invokes onFlush immediately without waiting for the timer', () {
        fakeAsync((async) {
          var flushCount = 0;
          final scheduler = BatchFlushScheduler(
            interval: interval,
            sizeThreshold: sizeThreshold,
            onFlush: () async => flushCount++,
            pendingCountProvider: () async => 0,
          );

          scheduler.flushNow();
          async.flushMicrotasks();

          expect(flushCount, 1);
        });
      });

      test(
          'second flushNow() while flush is in-progress runs after first completes',
          () {
        fakeAsync((async) {
          final completer = Completer<void>();
          var flushCount = 0;
          var simultaneous = 0;
          var maxSimultaneous = 0;

          final scheduler = BatchFlushScheduler(
            interval: interval,
            sizeThreshold: sizeThreshold,
            onFlush: () async {
              simultaneous++;
              maxSimultaneous =
                  simultaneous > maxSimultaneous ? simultaneous : maxSimultaneous;
              await completer.future;
              simultaneous--;
              flushCount++;
            },
            pendingCountProvider: () async => 0,
          );

          // Start first flush (will block on completer)
          scheduler.flushNow();
          async.flushMicrotasks();
          expect(flushCount, 0); // still waiting

          // Second flushNow() queues a re-run (rerequested = true)
          scheduler.flushNow();
          async.flushMicrotasks();

          // Complete the first flush
          completer.complete();
          async.flushMicrotasks();

          // After first completes, second should have run
          expect(flushCount, 2);
          // Max simultaneous should never exceed 1
          expect(maxSimultaneous, 1);
        });
      });
    });

    // -----------------------------------------------------------------------
    // notifyEnqueued
    // -----------------------------------------------------------------------
    group('notifyEnqueued', () {
      test(
          'triggers flush when pendingCountProvider returns >= sizeThreshold',
          () {
        fakeAsync((async) {
          var flushCount = 0;
          final scheduler = BatchFlushScheduler(
            interval: interval,
            sizeThreshold: sizeThreshold,
            onFlush: () async => flushCount++,
            pendingCountProvider: () async => sizeThreshold, // exactly at threshold
          );

          scheduler.notifyEnqueued();
          async.flushMicrotasks();

          expect(flushCount, 1);
        });
      });

      test('does NOT trigger flush when count is below sizeThreshold', () {
        fakeAsync((async) {
          var flushCount = 0;
          final scheduler = BatchFlushScheduler(
            interval: interval,
            sizeThreshold: sizeThreshold,
            onFlush: () async => flushCount++,
            pendingCountProvider: () async => sizeThreshold - 1, // below threshold
          );

          scheduler.notifyEnqueued();
          async.flushMicrotasks();

          expect(flushCount, 0);
        });
      });

      test(
          'rapid notifyEnqueued calls result in at most one concurrent flush',
          () {
        fakeAsync((async) {
          final completer = Completer<void>();
          var flushCount = 0;
          var concurrent = 0;
          var maxConcurrent = 0;

          final scheduler = BatchFlushScheduler(
            interval: interval,
            sizeThreshold: 1,
            onFlush: () async {
              concurrent++;
              maxConcurrent =
                  concurrent > maxConcurrent ? concurrent : maxConcurrent;
              await completer.future;
              concurrent--;
              flushCount++;
            },
            pendingCountProvider: () async => 5,
          );

          // Fire multiple notifyEnqueued calls rapidly
          scheduler.notifyEnqueued();
          scheduler.notifyEnqueued();
          scheduler.notifyEnqueued();
          async.flushMicrotasks();

          // Only one flush in flight
          expect(maxConcurrent, 1);

          completer.complete();
          async.flushMicrotasks();

          // One original + at most one re-run (rerequested coalesced)
          expect(flushCount, lessThanOrEqualTo(2));
          expect(maxConcurrent, 1);
        });
      });
    });
  });
}
