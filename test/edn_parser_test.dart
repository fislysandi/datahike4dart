import 'package:datahike4dart/src/edn.dart';
import 'package:test/test.dart';

void main() {
  group('EDN parser', () {
    test('parses nil', () {
      expect(parseEdn('nil'), isNull);
    });

    test('parses booleans', () {
      expect(parseEdn('true'), isTrue);
      expect(parseEdn('false'), isFalse);
    });

    test('parses integers', () {
      expect(parseEdn('42'), 42);
      expect(parseEdn('-7'), -7);
    });

    test('parses doubles', () {
      expect(parseEdn('3.14'), 3.14);
    });

    test('parses strings', () {
      expect(parseEdn('"hello"'), 'hello');
      expect(parseEdn('"with \\"quotes\\""'), 'with "quotes"');
    });

    test('parses keywords', () {
      expect(parseEdn(':name'), ':name');
      expect(parseEdn(':db/ident'), ':db/ident');
    });

    test('parses vectors', () {
      expect(parseEdn('[1 2 3]'), [1, 2, 3]);
    });

    test('parses lists', () {
      expect(parseEdn('(1 2 3)'), [1, 2, 3]);
    });

    test('parses sets', () {
      final result = parseEdn('#{1 2 3}');
      expect(result, isA<Set>());
      expect(result, containsAll([1, 2, 3]));
    });

    test('parses maps', () {
      final result = parseEdn('{:a 1 :b 2}') as Map;
      expect(result[':a'], 1);
      expect(result[':b'], 2);
    });

    test('parses nested structures', () {
      final result = parseEdn('[{:name "Alice"} {:name "Bob"}]') as List;
      expect(result.length, 2);
      expect((result[0] as Map)[':name'], 'Alice');
    });

    test('parses query result set of vectors', () {
      final result = parseEdn('#{[1 "Alice"] [2 "Bob"]}');
      expect(result, isA<Set>());
      final set = result as Set;
      expect(set.length, 2);
    });

    test('parses datoms list', () {
      final result = parseEdn('([1 :name "Alice"])') as List;
      expect(result.length, 1);
      expect(result[0], [1, ':name', 'Alice']);
    });

    test('parses all top-level values', () {
      final result = parseEdnAll('1 2 3');
      expect(result, [1, 2, 3]);
    });

    test('throws on invalid input', () {
      expect(() => parseEdn('{:a'), throwsFormatException);
    });
  });
}
