import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logger/web.dart';

import 'package:openpanel_flutter/src/models/batch_payload.dart';
import 'package:openpanel_flutter/src/models/open_panel_event_options.dart';
import 'package:openpanel_flutter/src/models/open_panel_options.dart';
import 'package:openpanel_flutter/src/models/open_panel_state.dart';
import 'package:openpanel_flutter/src/models/post_event_payload.dart';
import 'package:openpanel_flutter/src/models/update_profile_payload.dart';
import 'package:openpanel_flutter/src/observers/batch_lifecycle_observer.dart';
import 'package:openpanel_flutter/src/observers/referrer_observer.dart';
import 'package:openpanel_flutter/src/services/batch_drainer.dart';
import 'package:openpanel_flutter/src/services/batch_flush_scheduler.dart';
import 'package:openpanel_flutter/src/services/database/event_queue_database.dart';
import 'package:openpanel_flutter/src/services/event_queue.dart';
import 'package:openpanel_flutter/src/services/openpanel_http_client.dart';
import 'package:openpanel_flutter/src/services/preferences_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:openpanel_flutter/src/utils/insert_id_generator.dart';

/// A LogOutput that writes to the console AND forwards each log line to an
/// optional registered callback.  Used by the debug screen to capture SDK logs.
class _CallbackLogOutput extends LogOutput {
  void Function(String)? _listener;

  void setListener(void Function(String)? listener) {
    _listener = listener;
  }

  @override
  void output(OutputEvent event) {
    // Mirror to console.
    for (final line in event.lines) {
      // ignore: avoid_print
      print(line);
    }
    // Forward to listener (e.g., debug screen).
    final listener = _listener;
    if (listener != null) {
      for (final line in event.lines) {
        listener(line);
      }
    }
  }
}

class Openpanel {
  /// Openpanel instance
  ///
  /// Example:
  /// ```dart
  /// Openpanel.instance.event(name: 'screen_view', properties: {
  ///   'my_event': eventName,
  ///})
  ///```
  static final Openpanel instance = Openpanel._internal();

  factory Openpanel() => instance;

  Openpanel._internal();

  final _CallbackLogOutput _callbackOutput = _CallbackLogOutput();

  late final Logger _logger;

  /// A [ValueNotifier] updated after every successful batch flush.
  /// Listeners (e.g., the debug screen) are notified with the latest [BatchResponse].
  static final ValueNotifier<BatchResponse?> lastBatchResponse =
      ValueNotifier<BatchResponse?>(null);

  late final OpenpanelOptions options;
  late final PreferencesService _preferencesService;

  late final OpenpanelHttpClient _httpClient;

  bool _isClientInitialised = false;

  OpenpanelState _state = const OpenpanelState();

  // Batching components — only non-null when batchingEnabled.
  EventQueue? _eventQueue;
  BatchFlushScheduler? _scheduler;
  BatchLifecycleObserver? _lifecycleObserver;
  BatchDrainer? _drainer;

  /// Initialise Openpanel.
  /// This must be called before using Openpanel.
  ///
  ///  - [options]
  ///    - [url] - Openpanel url
  ///    - [clientId] - Openpanel client id
  ///    - [clientSecret] - Openpanel client secret
  ///    - [verbose] - Enable verbose logging
  ///
  /// Example:
  /// ```dart
  /// Openpanel.instance.initialize(
  ///   options: OpenpanelOptions(
  ///     url: <YOUR_OPENPANEL_URL>, // optional
  ///     clientId: <YOUR_CLIENT_ID>,
  ///     clientSecret: <YOUR_CLIENT_SECRET>,
  ///     verbose: true, // optional, defaults to false
  ///   ),
  ///)
  ///```
  Future<void> initialize({required OpenpanelOptions options}) async {
    if (_isClientInitialised) {
      return;
    }
    this.options = options;

    // Initialise logger with our combined output (console + debug callback).
    _logger = Logger(output: _callbackOutput);

    _preferencesService =
        PreferencesService(await SharedPreferences.getInstance());

    final OpenpanelState? savedState =
        await _preferencesService.getSavedState();
    if (savedState != null) {
      _state = savedState;
    } else {
      final deviceData = await _getTrackedDeviceData();

      double rate = options.tracingSampleRate;
      bool sampled = rate >= 1.0 || Random().nextDouble() < rate;

      if (deviceData.isNotEmpty) {
        setGlobalProperties(deviceData);
        // profileId intentionally left null — logged-out users should not send
        // profileId in events. The server resolves identity via deviceId alone.
        // profileId is set later when the user explicitly calls updateProfile().
        _state = _state.copyWith(
          deviceId: deviceData['deviceId'] ?? const Uuid().v4(),
          isTracingSampled: sampled,
        );
      } else {
        _state = _state.copyWith(isTracingSampled: sampled);
      }

      _preferencesService.persistState(_state);
    }

    _httpClient = OpenpanelHttpClient(
      verbose: options.verbose,
      logger: _logger,
    );

    await _httpClient.init(options);

    WidgetsBinding.instance.addObserver(ReferrerObserver());

    if (options.batchingEnabled) {
      final db = EventQueueDatabase.open();
      _eventQueue = EventQueue(db, maxRetries: options.maxRetries, logger: _logger);

      _drainer = BatchDrainer(
        queue: _eventQueue!,
        batchFn: _httpClient.batch,
        maxBatchSize: options.maxBatchSize,
        maxEventAge: options.maxEventAge,
        logger: _logger,
        onResponse: (r) => lastBatchResponse.value = r,
      );

      _scheduler = BatchFlushScheduler(
        interval: options.flushInterval,
        sizeThreshold: options.maxBatchSize,
        onFlush: _drainQueue,
        pendingCountProvider: _eventQueue!.count,
        logger: _logger,
      );
      _scheduler!.start();

      _lifecycleObserver = BatchLifecycleObserver(
        onBackground: () => _scheduler!.flushNow(),
      );
      WidgetsBinding.instance.addObserver(_lifecycleObserver!);
    }

    _isClientInitialised = true;
  }

  /// Enable or disable collection. Enabled by default.
  void setCollectionEnabled(bool enabled) =>
      _state = _state.copyWith(isCollectionEnabled: enabled);

  /// Set profile id
  ///
  /// Profile ids are automatically generated if not set and never change unless you
  /// call [clear] to reset them, use this method or reinstall the app.
  void setProfileId(String profileId) =>
      _state = _state.copyWith(profileId: profileId);

  /// Update profile
  ///
  /// Update an existing profile to add additional infos
  void updateProfile({required UpdateProfilePayload payload}) {
    _execute(() {
      setProfileId(payload.profileId);
      final insertId = generateInsertId(_state.deviceId);
      if (options.batchingEnabled) {
        final now = DateTime.now().toUtc();
        final eventPayload = {
          ...payload.toJson(),
          'properties': {
            ...payload.properties,
            ..._state.properties,
            '__insert_id': insertId,
          },
          '__timestamp': now.toIso8601String(),
        };
        _enqueueEvent(type: 'identify', payload: eventPayload, occurredAt: now);
      } else {
        _httpClient.updateProfile(
          payload: payload,
          stateProperties: {
            ..._state.properties,
            '__insert_id': insertId,
          },
        );
      }
    });
  }

  /// Increment a property.
  ///
  /// Ex. You may want to increment the amount of time a user opened the app
  void increment({
    required String property,
    required int value,
    OpenpanelEventOptions? eventOptions,
  }) {
    _execute(() {
      final profileId = eventOptions?.profileId ?? _state.profileId;
      if (profileId == null) {
        return;
      }

      final insertId = generateInsertId(_state.deviceId);
      if (options.batchingEnabled) {
        final now = DateTime.now().toUtc();
        _enqueueEvent(
          type: 'increment',
          payload: {
            'profileId': profileId,
            'property': property,
            'value': value,
            '__timestamp': now.toIso8601String(),
            '__insert_id': insertId,
          },
          occurredAt: now,
        );
      } else {
        _httpClient.increment(
          profileId: profileId,
          property: property,
          value: value,
        );
      }
    });
  }

  /// Decrement property
  ///
  /// Ex. Decrease the number of credits the user has
  void decrement({
    required String property,
    required int value,
    OpenpanelEventOptions? eventOptions,
  }) {
    _execute(() {
      final profileId = eventOptions?.profileId ?? _state.profileId;
      if (profileId == null) {
        return;
      }

      final insertId = generateInsertId(_state.deviceId);
      if (options.batchingEnabled) {
        final now = DateTime.now().toUtc();
        _enqueueEvent(
          type: 'decrement',
          payload: {
            'profileId': profileId,
            'property': property,
            'value': value,
            '__timestamp': now.toIso8601String(),
            '__insert_id': insertId,
          },
          occurredAt: now,
        );
      } else {
        _httpClient.decrement(
          profileId: profileId,
          property: property,
          value: value,
        );
      }
    });
  }

  /// Send an event
  ///
  /// You can send events with any name and any properties. By default, the device
  /// infos such as id, branch, model, etc... will be sent.
  void event({
    required String name,
    Map<String, dynamic> properties = const {},
  }) {
    _execute(() async {
      final profileId = properties['profileId'] ?? _state.profileId;
      final mergedProps = {
        ..._state.properties,
        ...{...properties}..removeWhere((key, value) => key == 'profileId'),
      };
      final insertId = generateInsertId(_state.deviceId);

      if (options.batchingEnabled) {
        final now = DateTime.now().toUtc();
        _enqueueEvent(
          type: 'track',
          payload: PostEventPayload(
            name: name,
            deviceId: _state.deviceId,
            properties: {
              ...mergedProps,
              '__timestamp': now.toIso8601String(),
              '__insert_id': insertId,
            },
            profileId: profileId,
          ).toJson(),
          occurredAt: now,
        );
      } else {
        _httpClient.event(
          payload: PostEventPayload(
            name: name,
            deviceId: _state.deviceId,
            properties: {
              ...mergedProps,
              '__timestamp': DateTime.now().toUtc().toIso8601String(),
              '__insert_id': insertId,
            },
            profileId: profileId,
          ),
        );
      }
    });
  }

  /// Set global properties
  /// These properties will be sent every time an event is sent
  void setGlobalProperties(Map<String, dynamic> properties) {
    _state = _state.copyWith(properties: {
      ..._state.properties,
      ...properties,
    });
  }

  /// Clear all properties and queued events.
  /// Use this method if you want to reset the global properties.
  Future<void> clear() async {
    // Preserve deviceId and sampling — these are device-scoped, not user-scoped.
    // Resetting them would permanently lose the device identity because
    // initialize() skips UUID generation when a saved state already exists.
    // profileId is intentionally null — the server resolves logged-out users
    // via deviceId alone. Do NOT assign a random UUID here.
    _state = OpenpanelState(
      deviceId: _state.deviceId,
      isTracingSampled: _state.isTracingSampled,
    );
    await _preferencesService.persistState(_state);
    await _eventQueue?.deleteAll();
  }

  /// Explicitly flush any pending queued events to the server.
  /// No-op when batching is disabled.
  Future<void> flush() async {
    await _scheduler?.flushNow();
  }

  /// Gracefully stop the scheduler and close the database.
  ///
  /// Awaits a best-effort final flush before tearing down. The OS may kill the
  /// process before the network request completes; in that case, events remain
  /// in the local queue and are retried on the next launch.
  ///
  /// After [shutdown] returns, [initialize] may be called again to reinitialise
  /// the SDK (all batching components are reset).
  ///
  /// Call this during app teardown if you need explicit cleanup.
  Future<void> shutdown() async {
    // Best-effort flush — ignore errors; events stay queued for next launch.
    if (_scheduler != null) {
      try {
        await _scheduler!.flushNow();
      } catch (_) {
        // ignore
      }
    }

    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
    }
    _scheduler?.stop();
    await _eventQueue?.close();

    // Null out batching components so a subsequent initialize() re-runs the
    // full init flow.
    _scheduler = null;
    _eventQueue = null;
    _drainer = null;
    _lifecycleObserver = null;
    _isClientInitialised = false;
  }

  /// Returns the number of events currently pending in the local queue.
  /// Returns 0 when batching is disabled or before initialisation.
  Future<int> pendingEventCount() async =>
      _eventQueue != null ? await _eventQueue!.count() : 0;

  /// Register a callback that receives every SDK log line.
  /// Pass [null] to unregister. Useful for the debug screen's network log.
  void setDebugLogListener(void Function(String line)? listener) {
    _callbackOutput.setListener(listener);
  }

  void _enqueueEvent({
    required String type,
    required Map<String, dynamic> payload,
    required DateTime occurredAt,
  }) {
    _eventQueue!
        .enqueue(type: type, payload: payload, occurredAt: occurredAt)
        .then((_) {
      _scheduler!.notifyEnqueued();
    }).catchError((Object e, StackTrace st) {
      _logger.e('Failed to enqueue event', error: e, stackTrace: st);
      return null;
    });
  }

  Future<void> _drainQueue() => _drainer!.drainOnce();

  void _execute<T>(T Function() action) {
    if (!_isClientInitialised) {
      throw Exception(
          'Openpanel is not initialised. You must initialize Openpanel before using Openpanel.instance.');
    }

    if (!_state.isCollectionEnabled) {
      return;
    }

    if (!_state.isTracingSampled) return;

    action();

    _preferencesService.persistState(_state);
  }

  Future<Map<String, dynamic>> _getTrackedDeviceData() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    Map<String, dynamic> properties = {
      'appVersion': packageInfo.version,
      'buildNumber': packageInfo.buildNumber,
      'installerStore': packageInfo.installerStore,
    };

    if (kIsWeb) {
      final WebBrowserInfo webInfo = await deviceInfo.webBrowserInfo;
      properties.addAll({
        'deviceId': const Uuid().v4(),
        'brand': webInfo.browserName.name,
        'model': webInfo.platform ?? 'Web',
        'osVersion': webInfo.appVersion ?? 'Unknown',
        'userAgent': webInfo.userAgent ?? '',
      });
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      properties.addAll({
        'deviceId': androidInfo.id,
        'brand': androidInfo.brand,
        'model': androidInfo.model,
        'manufacturer': androidInfo.manufacturer,
        'osVersion': androidInfo.version.release,
      });
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final IosDeviceInfo iosDeviceInfo = await deviceInfo.iosInfo;
      properties.addAll({
        'deviceId': iosDeviceInfo.identifierForVendor,
        'brand': iosDeviceInfo.name,
        'model': iosDeviceInfo.model,
        'osVersion': iosDeviceInfo.systemVersion,
      });
    }

    return properties;
  }
}

