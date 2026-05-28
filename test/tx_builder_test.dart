import 'package:datahike4dart/datahike4dart.dart';
import 'package:test/test.dart';

void main() {
  group('SchemaAttribute', () {
    test('minimal attribute', () {
      const attr = SchemaAttribute(ident: ':name', valueType: ValueType.string);
      expect(
        attr.toEdn(),
        '{:db/ident :name :db/valueType :db.type/string '
        ':db/cardinality :db.cardinality/one}',
      );
    });

    test('attribute with all options', () {
      const attr = SchemaAttribute(
        ident: ':person/email',
        valueType: ValueType.string,
        cardinality: Cardinality.one,
        unique: Uniqueness.identity,
        index: true,
        fulltext: true,
      );
      final edn = attr.toEdn();
      expect(edn, contains(':db/ident :person/email'));
      expect(edn, contains(':db/valueType :db.type/string'));
      expect(edn, contains(':db/cardinality :db.cardinality/one'));
      expect(edn, contains(':db/unique :db.unique/identity'));
      expect(edn, contains(':db/index true'));
      expect(edn, contains(':db/fulltext true'));
    });

    test('many cardinality', () {
      const attr = SchemaAttribute(
        ident: ':tags',
        valueType: ValueType.string,
        cardinality: Cardinality.many,
      );
      expect(attr.toEdn(), contains(':db.cardinality/many'));
    });
  });

  group('dbAdd / dbRetract', () {
    test('dbAdd produces correct EDN', () {
      expect(
        dbAdd(eid: 1, attr: ':name', value: '"Alice"'),
        '[:db/add 1 :name "Alice"]',
      );
    });

    test('dbRetract produces correct EDN', () {
      expect(
        dbRetract(eid: 1, attr: ':name', value: '"Alice"'),
        '[:db/retract 1 :name "Alice"]',
      );
    });
  });

  group('ednValue', () {
    test('nil', () => expect(ednValue(null), 'nil'));
    test('bool', () {
      expect(ednValue(true), 'true');
      expect(ednValue(false), 'false');
    });
    test('int', () => expect(ednValue(42), '42'));
    test('double', () => expect(ednValue(3.14), '3.14'));
    test('string', () => expect(ednValue('hello'), '"hello"'));
    test('string with quotes', () {
      expect(ednValue('say "hi"'), '"say \\"hi\\""');
    });
    test('DateTime', () {
      final dt = DateTime.utc(2024, 1, 15, 10, 30);
      expect(ednValue(dt), '#inst "2024-01-15T10:30:00.000Z"');
    });
    test('List', () {
      expect(ednValue([1, 'a']), '[1 "a"]');
    });
    test('Map', () {
      expect(ednValue({':a': 1, ':b': 2}), '{:a 1 :b 2}');
    });
    test('Map with string values', () {
      expect(
        ednValue({':name': 'Alice', ':age': '30'}),
        '{:name "Alice" :age "30"}',
      );
    });
  });

  group('txData / schemaTx', () {
    test('txData joins operations', () {
      expect(
        txData([
          dbAdd(eid: 1, attr: ':name', value: '"Alice"'),
          dbAdd(eid: 1, attr: ':age', value: '30'),
        ]),
        '[[:db/add 1 :name "Alice"] [:db/add 1 :age 30]]',
      );
    });

    test('schemaTx builds from attributes', () {
      final tx = schemaTx([
        const SchemaAttribute(ident: ':name', valueType: ValueType.string),
        const SchemaAttribute(ident: ':age', valueType: ValueType.long),
      ]);
      expect(tx, contains(':db/ident :name'));
      expect(tx, contains(':db/ident :age'));
      expect(tx, startsWith('['));
      expect(tx, endsWith(']'));
    });
  });

  group('entityMap', () {
    test('builds map-form entity', () {
      expect(
        entityMap({':name': '"Alice"', ':age': '30'}),
        '{:name "Alice" :age 30}',
      );
    });
  });
}
