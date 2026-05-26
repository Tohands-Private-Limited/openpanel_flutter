import 'package:flutter/widgets.dart';

/// Best-effort flush on app background.
///
/// Flushes the event queue whenever the app moves into a background-adjacent
/// state. The OS may kill the process before the network request completes;
/// in that case events remain in the local queue and are retried on next launch.
class BatchLifecycleObserver extends WidgetsBindingObserver {
  final Future<void> Function() onBackground;

  BatchLifecycleObserver({required this.onBackground});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      onBackground();
    }
  }
}
