/// Openpanel options
///
/// This is used to configure Openpanel
class OpenpanelOptions {
  /// This is the base url of the Openpanel API.
  /// You may want to change this if you are using a self-hosted version of Openpanel.
  ///
  /// Default value is: https://api.openpanel.dev
  final String? url;

  /// Your Openpanel client id.
  final String clientId;

  /// Your Openpanel client secret.
  final String? clientSecret;

  /// Enable verbose logging
  final bool verbose;

  /// Percentage of sessions that will be sampled for tracing (0.0 - 1.0)
  final double tracingSampleRate;

  /// Enable batched event delivery via the `{"type": "batch"}` envelope on `/track`.
  /// When true, events are persisted locally in SQLite and flushed in batches.
  /// Default is `false` — opt-in only, preserving identical behavior for existing users.
  final bool batchingEnabled;

  /// How often the flush scheduler fires to send pending events to the server.
  /// Only relevant when [batchingEnabled] is true.
  final Duration flushInterval;

  /// Maximum number of events to include in a single batch request.
  /// Also acts as the size threshold that triggers an immediate flush.
  /// Only relevant when [batchingEnabled] is true.
  final int maxBatchSize;

  /// Maximum number of delivery attempts before a permanently-failing event is dropped.
  /// Only relevant when [batchingEnabled] is true.
  final int maxRetries;

  /// Drop queued events older than this age before each drain. The openpanel
  /// server rejects events whose timestamp is more than 5 days old, so anything
  /// older has no chance of being accepted. Default: 5 days.
  /// Only relevant when [batchingEnabled] is true.
  final Duration maxEventAge;

  OpenpanelOptions({
    this.url,
    required this.clientId,
    this.clientSecret,
    this.verbose = false,
    this.tracingSampleRate = 1.0,
    this.batchingEnabled = false,
    this.flushInterval = const Duration(seconds: 60),
    this.maxBatchSize = 50,
    this.maxRetries = 5,
    this.maxEventAge = const Duration(days: 5),
  });
}
