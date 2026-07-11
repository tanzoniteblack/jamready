# JamReady

JamReady is a Flutter app for managing a Roller Derby jam timer. It supports both standalone (offline) mode and remote mode, where it connects to a [CRG Derby Scoreboard](https://github.com/rollerderby/scoreboard) instance over WebSocket and acts as a remote control.

## Prerequisites

- Flutter SDK 3.41.6 (the version pinned in CI)
- Dart SDK (comes with Flutter)
- Xcode (for iOS/macOS) and/or Android Studio (for Android)

Verify your environment:

```bash
flutter doctor
```

## Setup

```bash
flutter pub get --enforce-lockfile
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

```bash
make unit        # unit and widget tests (no device required)
make integration # offline integration test (requires a connected device or emulator)
make test        # both of the above
```

## Scoreboard Integration Tests

The scoreboard tests connect to a real CRG scoreboard over WebSocket and verify compatibility across multiple versions. They require Docker and git (the scoreboard build runs entirely inside Docker — no local JDK or Ant needed).

Build the scoreboard images once before running either suite. You can build every supported version or select specific versions:

```bash
make build-scoreboards
./scripts/build-scoreboard-images.sh --versions v2025.9,v2025.8
```

The source for each scoreboard version is cloned and compiled inside a multi-stage Docker build (`scripts/scoreboard.Dockerfile`).

### Headless remote-engine suite

The fast suite exercises `RemoteGameEngine` and `ScoreboardState` directly, without building the app or launching an emulator. It runs against every scoreboard image, newest version first, stops on the first failure, and writes a Flutter JSON report for each version to `test-results/`.

```bash
./scripts/test-remote-engine-scoreboards.sh
./scripts/test-remote-engine-scoreboards.sh --versions v2025.9,v2025.8
```

Useful options:

```
--versions     Comma-separated list of versions to test
--host         Host address the tests connect to (default: 127.0.0.1)
--port         Docker host port (default: 8001)
--results-dir  JSON report directory (default: test-results)
```

Arguments after `--` are passed to `flutter test`.

### App integration suite

The UI-driven suite builds and controls the Flutter app on an Android emulator. It also runs against each scoreboard image, newest version first, and stops on the first failure.

```bash
make test-scoreboards
./scripts/test-all-scoreboards.sh --versions v2025.9,v2025.8
```

Useful options:

```text
--versions  Comma-separated list of versions to test
--avd       AVD name (default: first from `emulator -list-avds`)
--host      Host address the tests connect to (default: 10.0.2.2)
--port      Docker host port (default: 8001)
```

Arguments after `--` are passed to `flutter test`.

### Continuous integration

The main CI workflow runs static analysis and unit/widget tests on pushes and pull requests to `main`. Test results are uploaded as JSON artifacts and published as a GitHub Check. Pull requests also run the headless remote-engine suite as a matrix across the supported CRG scoreboard versions, with a separate artifact and check for each version. The older `v2023.7` scoreboard is currently excluded from that CI matrix while its failing test is investigated.

## Releasing

The release script handles versioning, changelog generation, and tagging. It requires the [`claude` CLI](https://claude.ai/download) to generate the changelog.

```bash
./scripts/release.sh
```

It will ask whether this is a stable or pre-release, which version component to bump, and (for pre-releases) a suffix like `rc1` or `beta1`. It then generates a changelog from commits since the last release using Claude, shows it for confirmation, commits the version bump to `pubspec.yaml`, creates an annotated git tag, and offers to push. Pushing the tag triggers the GitHub Actions release workflow, which publishes a GitHub release with the changelog as the release notes.

### Store builds (manual)

The GitHub release contains release notes only — store builds must be created and uploaded manually using `make release`, which runs all tests (including scoreboard compatibility tests) and then builds both artifacts:

```bash
make release
```

This requires:

- A connected Android device or emulator for the integration tests
- `android/key.properties` pointing to your upload keystore (not checked in) for the Android build:
  ```
  storeFile=/path/to/upload-keystore.jks
  storePassword=...
  keyAlias=upload
  keyPassword=...
  ```
- Xcode with a valid signing certificate and provisioning profile for the iOS build

Once built, upload the artifacts via their respective consoles:
- **Android**: `build/app/outputs/bundle/release/app-release.aab` → Play Console
- **iOS**: `build/ios/ipa/*.ipa` → Xcode Organizer or `xcrun altool`

## Static Analysis

```bash
flutter analyze
```

## Project Structure

```
lib/                 app source (screens, widgets, models, services)
test/                unit and widget tests
integration_test/    integration tests (run separately)
remote_engine_test/  headless CRG scoreboard compatibility tests
assets/              app assets
scripts/             build and test utilities
```
