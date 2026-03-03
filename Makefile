.PHONY: unit integration test build-ios build-android release

# Run unit and widget tests only (fast, no device required)
unit:
	flutter test

# Run integration tests (requires a connected device or running simulator)
integration:
	flutter test integration_test

# Run all tests
test: unit integration

# Build iOS release archive only (tests must pass first)
build-ios: test
	flutter build ipa

# Build Android App Bundle only (tests must pass first)
build-android: test
	flutter build appbundle --release

# Run all tests, then build both release artifacts
release: test
	flutter build ipa
	flutter build appbundle --release
