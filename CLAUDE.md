# Development
- Use `flutter packages get` to install dependencies.
- Use `flutter run` to run the app.
- Write the code in a maintainable style, utilizing common DRY and KISS standards.
- Functional programming is encouraged.

# Releases
- Cut a release with `scripts/release.sh`: it bumps `pubspec.yaml`, tags, and opens the release PR.
- Build the release artifacts with the Makefile (`make release`, or `make build-ios` / `make build-android`), never with a bare `flutter build`. The Makefile passes the matching git tag via `--dart-define=RELEASE_TAG`, so the About screen shows e.g. `2.0.0-beta3`.
- Build after the release PR is merged and with a clean working tree; otherwise `scripts/release-tag.sh` finds no matching tag and the app shows only the pubspec version.

# Tests

There are two test directories, `test` and `integration_test`. `integration_test` does not get picked up automatically by `flutter test` and needs run specifically. If there's a physical android device available, run the integration tests on that, otherwise use the simulator.

When making functionality changes or UI changes that effect the actual use of the app, not just appearance, make sure to run the tests and validate that we didn't break anything or make a test case invalid. Add new tests when appropriate.