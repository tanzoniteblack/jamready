# JamReady

JamReady is a Flutter app for managing a Roller Derby jam timer. It supports both standalone (offline) mode and remote mode, where it connects to a [CRG Derby Scoreboard](https://github.com/rollerderby/scoreboard) instance over WebSocket and acts as a remote control.

## Prerequisites

- Flutter SDK (stable channel)
- Dart SDK (comes with Flutter)
- Xcode (for iOS/macOS) and/or Android Studio (for Android)

Verify your environment:

```bash
flutter doctor
```

## Setup

```bash
flutter pub get
```

## Running

List connected devices:

```bash
flutter devices
```

Run on a device:

```bash
flutter run -d <device-id>
```

## Testing

Run unit and widget tests:

```bash
flutter test
```

Run the offline integration test (requires a connected device or emulator):

```bash
flutter test integration_test/offline_game_integration_test.dart
```

## Scoreboard Integration Tests

The scoreboard integration tests connect to a live CRG scoreboard and verify compatibility across multiple versions. They require Docker, a Java 8+ JDK, and Apache Ant.

**Step 1 — Build the scoreboard Docker images:**

```bash
./scripts/build-scoreboard-images.sh
```

This clones `git@github.com:rollerderby/scoreboard.git` into `vendor/scoreboard` (not checked in) on first run, then builds a Docker image for each supported version.

**Step 2 — Run the tests:**

```bash
./scripts/test-all-scoreboards.sh
```

This runs the scoreboard integration test suite against each version sequentially, newest first, stopping on the first failure. It requires a connected Android device or emulator (the tests use the Android emulator's host alias to reach the Docker container).

Options:

```
--versions  Comma-separated list of versions to test
--avd       AVD name (default: first from `emulator -list-avds`)
--host      Host address the tests connect to (default: 10.0.2.2)
--port      Docker host port (default: 8001)
```

## Static Analysis

```bash
flutter analyze
```

## Project Structure

```
lib/                 app source (screens, widgets, models, services)
test/                unit and widget tests
integration_test/    integration tests (run separately)
assets/              app assets
scripts/             build and test utilities
vendor/              local dependencies (not checked in)
```
