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

```bash
make unit        # unit and widget tests (no device required)
make integration # offline integration test (requires a connected device or emulator)
make test        # both of the above
```

## Scoreboard Integration Tests

The scoreboard integration tests connect to a live CRG scoreboard and verify compatibility across multiple versions. They require Docker and git (the build runs entirely inside Docker — no local JDK or Ant needed).

```bash
make build-scoreboards  # build a Docker image for each supported scoreboard version (run once)
make test-scoreboards   # run the full suite against each image, newest version first
```

The source for each scoreboard version is cloned and compiled inside a multi-stage Docker build (`scripts/scoreboard.Dockerfile`). The test suite requires a connected Android device or emulator, and stops on the first failure.

To pass options to the test runner (e.g. to test specific versions), call the script directly:

```bash
./scripts/test-all-scoreboards.sh --versions v2025.9,v2025.8
```

```
--versions  Comma-separated list of versions to test
--avd       AVD name (default: first from `emulator -list-avds`)
--host      Host address the tests connect to (default: 10.0.2.2)
--port      Docker host port (default: 8001)
```

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
assets/              app assets
scripts/             build and test utilities
```
