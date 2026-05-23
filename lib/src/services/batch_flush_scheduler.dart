import 'dart:async';

import 'package:logger/logger.dart';

class BatchFlushScheduler {
  final Duration _interval;
  final int _sizeThreshold;
  final Future<void> Function() _onFlush;
  final Future<int> Function() _pendingCountProvider;
  final Logger? _logger;

  Timer? _timer;
  bool _flushing = false;
  // When a second trigger arrives while a flush is in progress, we queue exactly one re-run.
  bool _rerequested = false;

  BatchFlushScheduler({
    required Duration interval,
    required int sizeThreshold,
    required Future<void> Function() onFlush,
    required Future<int> Function() pendingCountProvider,
    Logger? logger,
  })  : _interval = interval,
        _sizeThreshold = sizeThreshold,
        _onFlush = onFlush,
        _pendingCountProvider = pendingCountProvider,
        _logger = logger;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _triggerFlush());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> flushNow() async {
    if (_flushing) {
      _rerequested = true;
      // Wait for the current flush to complete before returning to the caller.
      await _waitForIdle();
      return;
    }
    await _doFlush();
  }

  void notifyEnqueued() {
    _pendingCountProvider().then((count) {
      if (count >= _sizeThreshold) {
        _triggerFlush();
      }
    });
  }

  void _triggerFlush() {
    if (_flushing) {
      _rerequested = true;
      return;
    }
    // Fire-and-forget; errors are caught inside _doFlush.
    _doFlush();
  }

  Future<void> _doFlush() async {
    _flushing = true;
    try {
      await _onFlush();
    } catch (e, st) {
      _logger?.e('BatchFlushScheduler: flush error', error: e, stackTrace: st);
    } finally {
      _flushing = false;
      if (_rerequested) {
        _rerequested = false;
        await _doFlush();
      }
    }
  }

  // Polls until no flush is in progress — used only by flushNow().
  Future<void> _waitForIdle() async {
    while (_flushing) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
