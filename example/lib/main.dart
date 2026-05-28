import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:openpanel_flutter/openpanel_flutter.dart';

import 'debug_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load credentials from .env.local; fall back to .env.example in CI.
  try {
    await dotenv.load(fileName: 'assets/.env.local');
  } catch (_) {
    debugPrint(
      '[openpanel] WARNING: assets/.env.local not found — falling back to '
      'assets/.env.example. These are placeholder credentials; events will '
      'NOT be accepted by the server.',
    );
    await dotenv.load(fileName: 'assets/.env.example');
  }

  await Openpanel.instance.initialize(
    options: OpenpanelOptions(
      url: dotenv.env['OPENPANEL_API_URL'],
      clientId: dotenv.env['OPENPANEL_CLIENT_ID'] ?? '',
      clientSecret: dotenv.env['OPENPANEL_CLIENT_SECRET'],
      batchingEnabled: true,
      flushInterval: const Duration(seconds: 30),
      maxBatchSize: 25,
      maxRetries: 5,
      verbose: true,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'openpanel_flutter demo',
      navigatorObservers: [OpenpanelObserver()],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      routes: {
        '/': (_) => const HomeScreen(),
        '/debug': (_) => const DebugScreen(),
      },
      initialRoute: '/',
    );
  }
}

// ---------------------------------------------------------------------------
// Home screen
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _clickCount = 0;

  void _trackButtonClick() {
    setState(() => _clickCount++);
    Openpanel.instance.event(
      name: 'button_clicked',
      properties: {'count': _clickCount},
    );
  }

  void _incrementClicks() {
    Openpanel.instance.increment(property: 'clicks', value: 1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Incremented 'clicks' by 1")),
    );
  }

  void _identify() {
    Openpanel.instance.setProfileId('user_123');
    Openpanel.instance.updateProfile(
      payload: const UpdateProfilePayload(
        profileId: 'user_123',
        firstName: 'Jane',
        lastName: 'Demo',
        email: 'jane@example.com',
        properties: {'plan': 'free'},
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Identified as user_123')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final op = Openpanel.instance;
    final opts = op.options;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('openpanel_flutter demo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SDK info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SDK Info',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _InfoRow('Base URL', opts.url ?? 'https://api.openpanel.dev'),
                    _InfoRow('Client ID', opts.clientId),
                    _InfoRow('Batching', opts.batchingEnabled ? 'enabled' : 'disabled'),
                    _InfoRow('Flush interval', '${opts.flushInterval.inSeconds}s'),
                    _InfoRow('Max batch size', '${opts.maxBatchSize}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Action buttons
            Text('Actions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            ElevatedButton(
              onPressed: _trackButtonClick,
              child: Text('Track button_clicked event (count: $_clickCount)'),
            ),
            const SizedBox(height: 8),

            ElevatedButton(
              onPressed: _incrementClicks,
              child: const Text("Increment 'clicks' by 1"),
            ),
            const SizedBox(height: 8),

            ElevatedButton(
              onPressed: _identify,
              child: const Text('Identify as user_123'),
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/debug'),
              icon: const Icon(Icons.bug_report),
              label: const Text('Open debug panel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
