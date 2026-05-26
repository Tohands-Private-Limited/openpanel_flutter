# openpanel_flutter example

A demo app for the `openpanel_flutter` SDK that showcases the opt-in **batch event tracking** pipeline.

## Setup

1. Copy the example env file and fill in your credentials:

   ```bash
   cp assets/.env.example assets/.env.local
   # then edit assets/.env.local with your real values
   ```

2. Install dependencies and run:

   ```bash
   flutter pub get
   flutter run
   ```

The app initialises the SDK with `batchingEnabled: true`, a 30-second flush interval, and a batch size of 25 so you can observe the queuing and delivery behaviour quickly.

## Debug screen

Tap **Open debug panel** on the home screen to open the batch-tracking debug view.  It lets you:

- See live pending event count (polled every second).
- Generate 10 or 100 test events to trigger size-threshold or timer flushes.
- Force an immediate flush and see elapsed time.
- Wipe the local queue and state.
- Watch a scrollable SDK log (network requests / responses / errors) in real time.
- Inspect the last batch response: accepted count, rejected count, and rejection details.

## Credentials

`assets/.env.local` is gitignored.  `assets/.env.example` is committed as a template so other developers know what values to provide.
