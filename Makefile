.PHONY: unit integration test build-scoreboards test-scoreboards build-ios build-android release

# Run unit and widget tests only (fast, no device required)
unit:
	flutter test

# Run integration tests (requires a connected device or running simulator)
integration:
	flutter test integration_test/offline_game_integration_test.dart

# Run all tests
test: unit integration

# Build Docker images for each scoreboard version (run once, before test-scoreboards)
build-scoreboards:
	./scripts/build-scoreboard-images.sh

# Run scoreboard integration tests against each Docker image
test-scoreboards: build-scoreboards
	./scripts/test-all-scoreboards.sh

# Build iOS release archive only (tests must pass first)
build-ios: test
	flutter build ipa

# Build Android App Bundle only (tests must pass first)
build-android: test
	flutter build appbundle --release

# Run all tests against all scoreboard versions, then build both release artifacts
release: test test-scoreboards
	flutter build ipa
	flutter build appbundle --release
