# JamReady

JamReady is a Flutter app for managing a Roller Derby jam timer, including support for remote scoreboard sessions compatible with CRG Derby Scoreboard.

## Prerequisites

- Flutter SDK (stable channel)
- Dart SDK (installed with Flutter)
- Xcode (for iOS/macOS targets) and/or Android Studio (for Android targets)

Verify your environment:

```bash
flutter doctor
```

## Setup

From the project root:

```bash
flutter pub get
```

## Run The App

List connected devices:

```bash
flutter devices
```

Run on the selected device:

```bash
flutter run
```

Run on a specific device:

```bash
flutter run -d <device-id>
```

## Testing

Run all unit/widget tests:

```bash
flutter test
```

Run a single test file:

```bash
flutter test test/widget_test.dart
```

Run integration tests (requires a running emulator/simulator or physical device as well as CRG scoreboard running):

```bash
flutter test integration_test
```

## Static Analysis

Run analyzer checks:

```bash
flutter analyze
```

## Project Structure

- `lib/` app source code (screens, widgets, models, services)
- `test/` unit and widget tests
- `integration_test/` integration tests
- `assets/` app assets
