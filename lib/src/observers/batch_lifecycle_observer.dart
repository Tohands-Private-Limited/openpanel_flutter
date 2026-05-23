import 'package:flutter/widgets.dart';

/// Flushes the event queue whenever the app moves into a background-adjacent
/// state so we don't lose events that haven't been sent yet.
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
