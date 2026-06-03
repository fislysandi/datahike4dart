/// Lightweight EDN parser focused on Datahike output patterns.
///
/// This is NOT a full EDN implementation. It covers the subset that
/// Datahike returns: strings, keywords, symbols, numbers, booleans,
/// nil, lists `(...)`, vectors `[...]`, sets `#{...}`, and maps `{...}`.
library;

import 'dart:collection';

/// Parses an EDN string into plain Dart objects.
///
/// Returned types:
/// - `null` for `nil`
/// - `bool` for `true` / `false`
/// - `int` or `double` for numbers
/// - `String` for strings and keywords (keywords keep the leading `:`)
/// - `List` for lists and vectors
/// - `Set` for sets
/// - `Map` for maps (keys are parsed values, usually keywords or strings)
Object? parseEdn(String input) {
  final parser = _EdnParser(input);
  final value = parser.parseValue();
  parser.skipWhitespace();
  if (!parser.isAtEnd) {
    throw FormatException(
      'Unexpected trailing characters at ${parser._position}',
      input,
      parser._position,
    );
  }
  return value;
}

/// Parses all top-level EDN values in [input] and returns them as a list.
List<Object?> parseEdnAll(String input) {
  final parser = _EdnParser(input);
  final values = <Object?>[];
  while (!parser.isAtEnd) {
    parser.skipWhitespace();
    if (parser.isAtEnd) break;
    values.add(parser.parseValue());
  }
  return values;
}

final class _EdnParser {
  _EdnParser(String input) : _input = input;

  final String _input;
  int _position = 0;

  bool get isAtEnd => _position >= _input.length;

  void skipWhitespace() {
    while (!isAtEnd) {
      final ch = _input[_position];
      if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == ',') {
        _position++;
      } else if (ch == ';') {
        // Skip comment to end of line.
        while (!isAtEnd && _input[_position] != '\n') {
          _position++;
        }
      } else {
        break;
      }
    }
  }

  Object? parseValue() {
    skipWhitespace();
    if (isAtEnd) {
      throw FormatException('Unexpected end of input', _input, _position);
    }

    final ch = _input[_position];

    return switch (ch) {
      'n' => _parseNil(),
      't' || 'f' => _parseBool(),
      '"' => _parseString(),
      ':' => _parseKeyword(),
      '(' => _parseList(),
      '[' => _parseVector(),
      '#' => _parseDispatch(),
      '{' => _parseMap(),
      '-' ||
      '+' ||
      '0' ||
      '1' ||
      '2' ||
      '3' ||
      '4' ||
      '5' ||
      '6' ||
      '7' ||
      '8' ||
      '9' => _parseNumber(),
      _ => _parseSymbol(),
    };
  }

  Object? _parseNil() {
    _expect('nil');
    return null;
  }

  bool _parseBool() {
    if (_peek('true')) {
      _expect('true');
      return true;
    }
    if (_peek('false')) {
      _expect('false');
      return false;
    }
    throw _error('Expected true or false');
  }

  String _parseString() {
    _consume('"');
    final buffer = StringBuffer();
    while (!isAtEnd && _input[_position] != '"') {
      if (_input[_position] == '\\') {
        _position++;
        if (isAtEnd) throw _error('Unterminated string escape');
        final esc = _input[_position];
        buffer.write(switch (esc) {
          '"' => '"',
          '\\' => '\\',
          'n' => '\n',
          'r' => '\r',
          't' => '\t',
          _ => esc,
        });
      } else {
        buffer.write(_input[_position]);
      }
      _position++;
    }
    _consume('"');
    return buffer.toString();
  }

  String _parseKeyword() {
    _consume(':');
    final start = _position;
    while (!isAtEnd && _isSymbolChar(_input[_position])) {
      _position++;
    }
    if (start == _position) throw _error('Empty keyword');
    return ':${_input.substring(start, _position)}';
  }

  List<Object?> _parseList() {
    _consume('(');
    final list = <Object?>[];
    while (!isAtEnd && _input[_position] != ')') {
      list.add(parseValue());
      skipWhitespace();
    }
    _consume(')');
    return list;
  }

  List<Object?> _parseVector() {
    _consume('[');
    final list = <Object?>[];
    while (!isAtEnd && _input[_position] != ']') {
      list.add(parseValue());
      skipWhitespace();
    }
    _consume(']');
    return list;
  }

  Object? _parseDispatch() {
    _consume('#');
    if (isAtEnd) throw _error('Unexpected # at end of input');
    final ch = _input[_position];
    if (ch == '{') {
      return _parseSet();
    }
    if (ch == '_') {
      // #_ discard reader macro
      _consume('_');
      parseValue(); // discard
      return parseValue();
    }
    if (ch == '"') {
      // regex literal — treat as string for now
      return _parseString();
    }
    // Tagged literal e.g. #uuid "..."
    final tag = _parseSymbolRaw();
    skipWhitespace();
    final value = parseValue();
    return _TaggedLiteral(tag, value);
  }

  Set<Object?> _parseSet() {
    _consume('{');
    final set = LinkedHashSet<Object?>(
      equals: _deepEquals,
      hashCode: _deepHash,
    );
    while (!isAtEnd && _input[_position] != '}') {
      set.add(parseValue());
      skipWhitespace();
    }
    _consume('}');
    return set;
  }

  Map<Object?, Object?> _parseMap() {
    _consume('{');
    final map = <Object?, Object?>{};
    while (!isAtEnd && _input[_position] != '}') {
      final key = parseValue();
      skipWhitespace();
      final value = parseValue();
      map[key] = value;
      skipWhitespace();
    }
    _consume('}');
    return map;
  }

  Object? _parseNumber() {
    final start = _position;
    if (_input[_position] == '-' || _input[_position] == '+') {
      _position++;
    }
    var hasDot = false;
    while (!isAtEnd) {
      final ch = _input[_position];
      if (ch == '.') {
        if (hasDot) break;
        hasDot = true;
        _position++;
      } else if (ch == 'e' || ch == 'E') {
        _position++;
        if (!isAtEnd &&
            (_input[_position] == '-' || _input[_position] == '+')) {
          _position++;
        }
      } else if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
        _position++;
      } else {
        break;
      }
    }
    final raw = _input.substring(start, _position);
    // Consume optional Clojure BigDecimal (M) or BigInt (N) suffix
    if (!isAtEnd && (_input[_position] == 'M' || _input[_position] == 'N')) {
      _position++;
    }
    if (hasDot) {
      return double.parse(raw);
    }
    return int.parse(raw);
  }

  String _parseSymbol() {
    final start = _position;
    while (!isAtEnd && _isSymbolChar(_input[_position])) {
      _position++;
    }
    if (start == _position) throw _error('Unexpected character');
    return _input.substring(start, _position);
  }

  String _parseSymbolRaw() {
    final start = _position;
    while (!isAtEnd && _isSymbolChar(_input[_position])) {
      _position++;
    }
    if (start == _position) throw _error('Empty symbol');
    return _input.substring(start, _position);
  }

  bool _isSymbolChar(String ch) {
    final code = ch.codeUnitAt(0);
    return ch == '/' ||
        ch == '.' ||
        ch == '*' ||
        ch == '!' ||
        ch == '?' ||
        ch == '_' ||
        ch == '-' ||
        ch == '+' ||
        ch == '=' ||
        ch == '<' ||
        ch == '>' ||
        ch == '&' ||
        ch == '%' ||
        ch == '#' ||
        ch == '\$' ||
        ch == '@' ||
        ch == '^' ||
        (code >= 65 && code <= 90) || // A-Z
        (code >= 97 && code <= 122) || // a-z
        (code >= 48 && code <= 57); // 0-9
  }

  void _consume(String expected) {
    if (isAtEnd || _input[_position] != expected) {
      throw _error('Expected "$expected"');
    }
    _position++;
  }

  bool _peek(String text) {
    return _input.startsWith(text, _position);
  }

  void _expect(String text) {
    if (!_peek(text)) throw _error('Expected "$text"');
    _position += text.length;
  }

  FormatException _error(String message) {
    return FormatException(message, _input, _position);
  }
}

final class _TaggedLiteral {
  const _TaggedLiteral(this.tag, this.value);

  final String tag;
  final Object? value;

  @override
  String toString() => '#$tag $value';

  @override
  bool operator ==(Object other) =>
      other is _TaggedLiteral && other.tag == tag && other.value == value;

  @override
  int get hashCode => Object.hash(tag, value);
}

bool _deepEquals(Object? a, Object? b) {
  if (a == b) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is Set && b is Set) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.any((x) => _deepEquals(x, item))) return false;
    }
    return true;
  }
  return false;
}

int _deepHash(Object? o) {
  if (o is List) {
    return Object.hashAll(o.map(_deepHash));
  }
  if (o is Map) {
    return Object.hashAll(
      o.entries.map((e) => Object.hash(_deepHash(e.key), _deepHash(e.value))),
    );
  }
  if (o is Set) {
    return Object.hashAll(o.map(_deepHash));
  }
  return o.hashCode;
}
