# datahike4dart development helpers

.PHONY: all deps format analyze test test-all fetch-native clean publish-dry-run

all: format analyze test

deps:
	dart pub get

format:
	dart format lib test example tool example_flutter

analyze:
	dart analyze --fatal-infos

test:
	dart test --exclude-tags=isolate

test-all:
	dart test

test-isolate:
	dart test --tags=isolate

fetch-native:
	dart tool/fetch_datahike_native.dart

publish-dry-run:
	dart pub publish --dry-run

clean:
	rm -rf .dart_tool/ build/ coverage/

# Run full CI checks locally
ci: format analyze test publish-dry-run
