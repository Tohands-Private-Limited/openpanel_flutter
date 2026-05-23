import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openpanel_flutter/openpanel_flutter.dart';

/// Debug screen for testing the batch-tracking pipeline end-to-end.
/// Shows batching config, lets you generate test events, force-flush,
/// wipe the queue, and view a live log of all SDK output.
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  // Pending event count, polled every second.
  int _pendingCount = 0;
  Timer? _pollTimer;

  // Network / SDK log lines (capped at 200).
  final List<String> _logLines = [];
  final ScrollController _logScroll = ScrollController();

  // Last batch response info.
  BatchResponse? _lastResponse;
  DateTime? _lastFlushTime;

  @override
  void initState() {
    super.initState();

    // Poll pending count every second.
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _refreshCount());
    _refreshCount();

    // Register log listener so every SDK log line lands in our list.
    Openpanel.instance.setDebugLogListener(_onLogLine);

    // Listen to batch response updates.
    Openpanel.lastBatchResponse.addListener(_onBatchResponse);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    Openpanel.instance.setDebugLogListener(null);
    Openpanel.lastBatchResponse.removeListener(_onBatchResponse);
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _refreshCount() async {
    final count = await Openpanel.instance.pendingEventCount();
    if (mounted) setState(() => _pendingCount = count);
  }

  void _onLogLine(String line) {
    if (!mounted) return;
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logLines.add('[$ts] $line');
      if (_logLines.length > 200) _logLines.removeAt(0);
    });
    // Scroll to bottom after frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  void _onBatchResponse() {
    if (!mounted) return;
    setState(() {
      _lastResponse = Openpanel.lastBatchResponse.value;
      _lastFlushTime = DateTime.now();
    });
  }

  void _generateEvents(int count) {
    for (var i = 0; i < count; i++) {
      Openpanel.instance.event(
        name: 'debug_test',
        properties: {'i': i, 'batch_size': count},
      );
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Queued $count test events')),
    );
  }

  Future<void> _forceFlush() async {
    final sw = Stopwatch()..start();
    await Openpanel.instance.flush();
    sw.stop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Flushed in ${sw.elapsedMilliseconds}ms')),
    );
  }

  Future<void> _wipeQueue() async {
    await Openpanel.instance.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Queue wiped and state cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opts = Openpanel.instance.options;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Debug Panel'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Batching status ──────────────────────────────────────────────
          _SectionHeader('Batching Status'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusRow('batchingEnabled', '${opts.batchingEnabled}',
                      opts.batchingEnabled ? Colors.green : Colors.orange),
                  _StatusRow(
                      'flushInterval', '${opts.flushInterval.inSeconds}s'),
                  _StatusRow('maxBatchSize', '${opts.maxBatchSize}'),
                  _StatusRow('maxRetries', '${opts.maxRetries}'),
                  const Divider(),
                  Row(
                    children: [
                      const Text('Pending events:',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Text(
                        '$_pendingCount',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _pendingCount > 0
                              ? Colors.orange
                              : Colors.green,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _refreshCount,
                        tooltip: 'Refresh count',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Actions ──────────────────────────────────────────────────────
          _SectionHeader('Actions'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: () => _generateEvents(10),
                child: const Text('Generate 10 events'),
              ),
              ElevatedButton(
                onPressed: () => _generateEvents(100),
                child: const Text('Generate 100 events'),
              ),
              ElevatedButton.icon(
                onPressed: _forceFlush,
                icon: const Icon(Icons.upload),
                label: const Text('Force flush'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _wipeQueue,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Wipe queue & state'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Last batch response ──────────────────────────────────────────
          _SectionHeader('Last Batch Response'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _lastResponse == null
                  ? const Text('No flush yet — tap "Force flush" to try.',
                      style: TextStyle(color: Colors.grey))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_lastFlushTime != null)
                          Text(
                            'At ${_lastFlushTime!.toLocal()}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        const SizedBox(height: 8),
                        _StatusRow(
                            'Accepted', '${_lastResponse!.accepted}',
                            Colors.green),
                        _StatusRow(
                            'Rejected', '${_lastResponse!.rejected.length}',
                            _lastResponse!.rejected.isEmpty
                                ? Colors.green
                                : Colors.red),
                        if (_lastResponse!.rejected.isNotEmpty) ...[
                          const Divider(),
                          const Text('Rejections:',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                          ...(_lastResponse!.rejected.map((r) => Padding(
                                padding:
                                    const EdgeInsets.only(top: 4),
                                child: Text(
                                  '[${r.index}] ${r.reason}: ${r.error}',
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: Colors.red),
                                ),
                              ))),
                        ],
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Network / SDK log ────────────────────────────────────────────
          Row(
            children: [
              Expanded(child: _SectionHeader('SDK Log')),
              TextButton.icon(
                onPressed: () => setState(() => _logLines.clear()),
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear'),
              ),
            ],
          ),
          Card(
            color: Colors.black87,
            child: SizedBox(
              height: 300,
              child: _logLines.isEmpty
                  ? const Center(
                      child: Text('Waiting for log output…',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: _logScroll,
                      padding: const EdgeInsets.all(8),
                      itemCount: _logLines.length,
                      itemBuilder: (_, i) => Text(
                        _logLines[i],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.greenAccent,
                          height: 1.4,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helper widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatusRow(this.label, this.value, [this.valueColor]);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: valueColor,
              fontWeight: valueColor != null ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
    );
  }
}
