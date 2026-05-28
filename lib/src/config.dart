/// Schema-flexibility mode for a Datahike database.
enum SchemaFlexibility {
  /// Strict schema mode (default). Only attributes defined in the schema
  /// can be transacted.
  read('read'),

  /// Flexible schema mode. New attributes are automatically added to the
  /// schema on first use.
  write('write');

  const SchemaFlexibility(this.ednName);

  final String ednName;
}

/// Base class for Datahike store configurations.
sealed class DatahikeStoreConfig {
  const DatahikeStoreConfig();

  /// Serializes this store config to an EDN map fragment.
  String toEdn();
}

/// File-backed store configuration.
final class DatahikeFileStore extends DatahikeStoreConfig {
  const DatahikeFileStore({required this.path, required this.id});

  /// Filesystem path to the database directory.
  final String path;

  /// UUID string that uniquely identifies this database store.
  final String id;

  @override
  String toEdn() {
    final escapedPath = _escapeString(path);
    return '{:backend :file :path "$escapedPath" :id #uuid "$id"}';
  }
}

/// In-memory store configuration.
final class DatahikeMemoryStore extends DatahikeStoreConfig {
  const DatahikeMemoryStore({required this.id});

  /// UUID string that uniquely identifies this database store.
  final String id;

  @override
  String toEdn() => '{:backend :mem :id #uuid "$id"}';
}

/// Immutable configuration for creating or connecting to a Datahike database.
///
/// Use the factory constructors [DatahikeConfig.file] or
/// [DatahikeConfig.memory] for typical cases, or [DatahikeConfig.fromEdn]
/// to wrap an existing raw EDN config string.
final class DatahikeConfig {
  const DatahikeConfig._({
    required this.store,
    this.schemaFlexibility,
    this.keepHistory,
    this.initialTx,
  });

  /// Creates a config backed by a file store.
  factory DatahikeConfig.file({
    required String path,
    required String id,
    SchemaFlexibility? schemaFlexibility,
    bool? keepHistory,
    String? initialTx,
  }) => DatahikeConfig._(
    store: DatahikeFileStore(path: path, id: id),
    schemaFlexibility: schemaFlexibility,
    keepHistory: keepHistory,
    initialTx: initialTx,
  );

  /// Creates a config backed by an in-memory store.
  factory DatahikeConfig.memory({
    required String id,
    SchemaFlexibility? schemaFlexibility,
    bool? keepHistory,
    String? initialTx,
  }) => DatahikeConfig._(
    store: DatahikeMemoryStore(id: id),
    schemaFlexibility: schemaFlexibility,
    keepHistory: keepHistory,
    initialTx: initialTx,
  );

  /// Wraps a raw EDN config string.
  ///
  /// The returned config is opaque — [toEdn] simply returns the original
  /// string. This preserves backward compatibility and advanced use cases.
  factory DatahikeConfig.fromEdn(String edn) => _RawDatahikeConfig(edn);

  /// Store-specific backend settings.
  final DatahikeStoreConfig store;

  /// Schema-flexibility mode.
  final SchemaFlexibility? schemaFlexibility;

  /// Whether to keep a full history of transactions.
  final bool? keepHistory;

  /// Optional initial transaction data as an EDN string.
  final String? initialTx;

  /// Serializes this config to a complete Datahike config EDN map.
  String toEdn() {
    final buffer = StringBuffer('{')..write(':store ${store.toEdn()}');

    if (schemaFlexibility case final sf?) {
      buffer.write(' :schema-flexibility :${sf.ednName}');
    }
    if (keepHistory case final kh?) {
      buffer.write(' :keep-history? $kh');
    }
    if (initialTx case final tx? when tx.isNotEmpty) {
      buffer.write(' :initial-tx $tx');
    }

    buffer.write('}');
    return buffer.toString();
  }
}

/// Opaque wrapper around a hand-written EDN config string.
final class _RawDatahikeConfig extends DatahikeConfig {
  const _RawDatahikeConfig(this._edn)
    : super._(
        store: const DatahikeMemoryStore(
          id: '00000000-0000-0000-0000-000000000000',
        ),
      );

  final String _edn;

  @override
  String toEdn() => _edn;
}

String _escapeString(String value) {
  return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}
