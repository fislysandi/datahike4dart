/// Datahike value types for schema attributes.
enum ValueType {
  string('string'),
  boolean('boolean'),
  long('long'),
  double('double'),
  bigDec('bigdec'),
  instant('instant'),
  ref('ref'),
  uuid('uuid'),
  uri('uri'),
  bytes('bytes');

  const ValueType(this.ednName);

  final String ednName;
}

/// Cardinality modes for schema attributes.
enum Cardinality {
  one('one'),
  many('many');

  const Cardinality(this.ednName);

  final String ednName;
}

/// Uniqueness constraints for schema attributes.
enum Uniqueness {
  value('value'),
  identity('identity');

  const Uniqueness(this.ednName);

  final String ednName;
}

/// Builder for a Datahike schema attribute definition.
///
/// ```dart
/// final attr = SchemaAttribute(
///   ident: ':name',
///   valueType: ValueType.string,
///   cardinality: Cardinality.one,
///   unique: Uniqueness.identity,
/// );
/// ```
final class SchemaAttribute {
  const SchemaAttribute({
    required this.ident,
    required this.valueType,
    this.cardinality = Cardinality.one,
    this.unique,
    this.index = false,
    this.fulltext = false,
    this.component = false,
    this.noHistory = false,
  });

  /// Attribute identifier, e.g. `:name` or `:person/name`.
  final String ident;

  /// Value type, e.g. [ValueType.string].
  final ValueType valueType;

  /// Cardinality, defaults to [Cardinality.one].
  final Cardinality cardinality;

  /// Uniqueness constraint, if any.
  final Uniqueness? unique;

  /// Whether to index this attribute for efficient lookup.
  final bool index;

  /// Whether to enable full-text search on this attribute.
  final bool fulltext;

  /// Whether this attribute references a component entity.
  final bool component;

  /// Whether to exclude this attribute from history.
  final bool noHistory;

  /// Serializes this attribute to an EDN map.
  String toEdn() {
    final buffer = StringBuffer('{');
    buffer.write(':db/ident ${_escapeKeyword(ident)} ');
    buffer.write(':db/valueType :db.type/${valueType.ednName} ');
    buffer.write(':db/cardinality :db.cardinality/${cardinality.ednName}');
    if (unique != null) {
      buffer.write(' :db/unique :db.unique/${unique!.ednName}');
    }
    if (index) buffer.write(' :db/index true');
    if (fulltext) buffer.write(' :db/fulltext true');
    if (component) buffer.write(' :db/isComponent true');
    if (noHistory) buffer.write(' :db/noHistory true');
    buffer.write('}');
    return buffer.toString();
  }
}

/// Transaction operation: add a fact.
///
/// ```dart
/// dbAdd(eid: 1, attr: ':name', value: '"Alice"')
/// ```
///
/// The [value] should already be an EDN literal (e.g. quoted string,
/// number, keyword, or nested map). Use [ednValue] to convert Dart values.
String dbAdd({required int eid, required String attr, required String value}) {
  return '[:db/add $eid ${_escapeKeyword(attr)} $value]';
}

/// Transaction operation: retract a fact.
String dbRetract({
  required int eid,
  required String attr,
  required String value,
}) {
  return '[:db/retract $eid ${_escapeKeyword(attr)} $value]';
}

/// Converts a Dart value to its EDN string representation.
///
/// - `null` -> `nil`
/// - `bool` -> `true` / `false`
/// - `int` / `double` -> number string
/// - `String` -> escaped `"..."`
/// - `DateTime` -> `#inst "..."`
/// - `List` -> `[...]`
/// - `Map` -> `{...}` (keys and values are recursively converted)
String ednValue(Object? value) {
  return switch (value) {
    null => 'nil',
    true => 'true',
    false => 'false',
    final int n => n.toString(),
    final double n => n.toString(),
    final String s => s.startsWith(':') ? s : '"${_escapeString(s)}"',
    final DateTime dt => '#inst "${_formatInst(dt)}"',
    final List<Object?> list => '[${list.map(ednValue).join(' ')}]',
    final Map<Object?, Object?> map =>
      '{${map.entries.map((e) => '${ednValue(e.key)} ${ednValue(e.value)}').join(' ')}}',
    _ => throw ArgumentError(
      'Unsupported EDN value: $value (${value.runtimeType})',
    ),
  };
}

/// Builds a transaction data vector from a list of EDN strings.
String txData(List<String> operations) => '[${operations.join(' ')}]';

/// Builds a schema transaction from a list of [SchemaAttribute] definitions.
String schemaTx(List<SchemaAttribute> attributes) {
  return txData(attributes.map((a) => a.toEdn()).toList());
}

/// Entity map-form transaction for insertion.
///
/// ```dart
/// entityMap({':name': '"Alice"', ':age': '30'})
/// ```
///
/// Values should be valid EDN literals. Use [ednValue] to convert Dart
/// values before passing them here.
String entityMap(Map<String, String> attrs) {
  final buffer = StringBuffer('{');
  buffer.writeAll(
    attrs.entries.map((e) => '${_escapeKeyword(e.key)} ${e.value}'),
    ' ',
  );
  buffer.write('}');
  return buffer.toString();
}

String _escapeKeyword(String value) {
  return value.startsWith(':') ? value : ':$value';
}

String _escapeString(String value) {
  return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}

String _formatInst(DateTime dt) {
  return dt.toUtc().toIso8601String();
}
