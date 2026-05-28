import 'dart:io';

import 'package:datahike4dart/datahike4dart.dart';
import 'package:test/test.dart';

void main() {
  test('DatahikeInput branch strips leading colon', () {
    final input = DatahikeInput.branch('{}', ':experiment');
    expect(input.format, 'branch:experiment');
    expect(input.value, '{}');
  });

  test('functional open reports missing native library as failure', () {
    if (Platform.environment.containsKey('DATAHIKE_LIB')) return;

    final result = DatahikeClient.open(libraryPath: '/missing/libdatahike.so');

    expect(result.isLeft(), isTrue);
    result.match(
      (failure) => expect(failure, isA<DatahikeLoadFailure>()),
      (_) => fail('Expected opening a missing native library to fail.'),
    );
  });

  test('raw open still throws for missing native library', () {
    if (Platform.environment.containsKey('DATAHIKE_LIB')) return;
    expect(
      () => Datahike.openRaw(libraryPath: '/missing/libdatahike.so'),
      throwsA(isA<ArgumentError>()),
    );
  });
}
