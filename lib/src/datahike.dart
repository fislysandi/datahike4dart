import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:fpdart/fpdart.dart';

import 'edn.dart';
import 'native_library.dart';

/// Supported native serialization formats.
enum DatahikeFormat {
  /// Extensible Data Notation format.
  edn('edn'),

  /// JavaScript Object Notation format.
  json('json'),

  /// Concise Binary Object Representation format.
  cbor('cbor');

  const DatahikeFormat(this.nativeName);

  final String nativeName;
}

/// An input passed to Datahike query/read operations.
///
/// Native Datahike accepts multiple input sources. For ordinary queries use
/// [DatahikeInput.database] with the database config EDN.
final class DatahikeInput {
  /// Creates a DatahikeInput with the given format and value.
  const DatahikeInput(this.format, this.value);

  /// Load the current database value by connecting with [configEdn].
  const DatahikeInput.database(String configEdn) : this('db', configEdn);

  /// Load the full history database by connecting with [configEdn].
  ///
  /// Unlike [DatahikeInput.database], this includes all historical versions
  /// of entities, enabling queries across the full transaction log.
  ///
  /// ```dart
  /// final input = DatahikeInput.history(config);
  /// final result = datahike.q('[:find ?e ?v :where [?e :name ?v]]', [input]);
  /// ```
  const DatahikeInput.history(String configEdn) : this('history', configEdn);

  /// Load the database as of [timestamp].
  ///
  /// Returns an input that represents the database state at the given timestamp.
  ///
  /// ```dart
  /// final input = DatahikeInput.asOf(config, DateTime(2026, 1, 1));
  /// final result = datahike.q('[:find ?e :where [?e :name ?n]]', [input]);
  /// ```
  factory DatahikeInput.asOf(String configEdn, DateTime timestamp) =>
      DatahikeInput('asof:${timestamp.millisecondsSinceEpoch}', configEdn);

  /// Load the database since [timestamp].
  ///
  /// Returns an input that represents the database state after the given
  /// timestamp (including changes made after it).
  ///
  /// ```dart
  /// final input = DatahikeInput.since(config, DateTime(2026, 6, 1));
  /// final result = datahike.q('[:find ?e :where [?e :name ?n]]', [input]);
  /// ```
  factory DatahikeInput.since(String configEdn, DateTime timestamp) =>
      DatahikeInput('since:${timestamp.millisecondsSinceEpoch}', configEdn);

  /// Load the database at a named branch.
  ///
  /// Returns an input that represents the database at the specified branch.
  ///
  /// ```dart
  /// final input = DatahikeInput.branch(config, ':experiment');
  /// final result = datahike.q('[:find ?e :where [?e :name ?n]]', [input]);
  /// ```
  factory DatahikeInput.branch(String configEdn, String branchName) =>
      DatahikeInput('branch:${_bareKeywordName(branchName)}', configEdn);

  /// Load the database at a commit UUID.
  ///
  /// Returns an input that represents the database at the specified commit.
  ///
  /// ```dart
  /// final input = DatahikeInput.commit(config, 'a1b2c3d4-...');
  /// final result = datahike.q('[:find ?e :where [?e :name ?n]]', [input]);
  /// ```
  factory DatahikeInput.commit(String configEdn, String commitUuid) =>
      DatahikeInput('commit:$commitUuid', configEdn);

  /// Pass raw EDN as an input value.
  const DatahikeInput.edn(String edn) : this('edn', edn);

  /// Pass raw JSON as an input value.
  const DatahikeInput.json(String json) : this('json', json);

  /// Pass raw CBOR as a base64/native string value.
  const DatahikeInput.cbor(String cbor) : this('cbor', cbor);

  /// The input format identifier (e.g., 'db', 'history', 'edn', 'json', 'cbor').
  final String format;

  /// The input value (e.g., EDN string, JSON string, CBOR string).
  final String value;
}

/// A typed failure returned by the public functional API.
abstract class DatahikeFailure {
  /// Creates a failure with the given message and optional cause.
  const DatahikeFailure(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Failed to load or initialize the native Datahike library.
///
/// This occurs when the native library cannot be found, fails to load,
/// or initialization fails for any reason.
final class DatahikeLoadFailure extends DatahikeFailure {
  /// Creates a load failure with the given message and optional cause.
  const DatahikeLoadFailure(super.message, [super.cause]);
}

/// Datahike returned a native exception.
///
/// This occurs when Datahike's native code throws an exception that
/// is returned as a string starting with 'exception:'.
final class DatahikeNativeFailure extends DatahikeFailure {
  /// Creates a native failure with the given message and optional cause.
  const DatahikeNativeFailure(super.message, [super.cause]);
}

/// The client was used after it was closed.
///
/// This occurs when attempting to use a DatahikeClient after calling close().
final class DatahikeClosedFailure extends DatahikeFailure {
  /// Creates a closed failure with the given message and optional cause.
  const DatahikeClosedFailure(super.message, [super.cause]);
}

/// The caller supplied invalid input before Datahike was invoked.
///
/// This occurs when the input parameters are invalid (e.g., null values,
/// incorrect types) before being passed to the native Datahike library.
final class DatahikeInvalidInputFailure extends DatahikeFailure {
  /// Creates an invalid input failure with the given message and optional cause.
  const DatahikeInvalidInputFailure(super.message, [super.cause]);
}

/// Thrown by the raw FFI layer when Datahike returns a native exception string.
///
/// This exception is thrown by the Datahike class when the native library
/// returns a string starting with 'exception:'.
final class DatahikeException implements Exception {
  /// Creates an exception with the given message.
  const DatahikeException(this.message);

  final String message;

  @override
  String toString() => 'DatahikeException: $message';
}

/// Functional result type used by the public API.
///
/// Represents either a [DatahikeFailure] or a successful value of type T.
typedef DatahikeResult<T> = Either<DatahikeFailure, T>;

/// Functional API for Datahike.
///
/// Methods return [Either] values so callers can handle failures without
/// exception-driven control flow. EDN strings are intentionally preserved as
/// the MVP data representation.
final class DatahikeClient {
  const DatahikeClient._(this._raw);

  /// Opens the native library and returns a functional client.
  static DatahikeResult<DatahikeClient> open({String? libraryPath}) =>
      Either.tryCatch(
        () => DatahikeClient._(Datahike.openRaw(libraryPath: libraryPath)),
        (error, _) => DatahikeLoadFailure(
          error is DatahikeException
              ? error.message
              : 'Failed to load or initialize Datahike native library.',
          error,
        ),
      );

  final Datahike _raw;

  /// Releases the native resources associated with this client.
  void close() => _raw.close();

  DatahikeResult<String> createDatabase(
    String configEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.createDatabase(configEdn, outputFormat: outputFormat),
  );

  DatahikeResult<String> deleteDatabase(
    String configEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.deleteDatabase(configEdn, outputFormat: outputFormat),
  );

  DatahikeResult<bool> databaseExists(String configEdn) =>
      _capture(() => _raw.databaseExists(configEdn));

  DatahikeResult<String> transact(
    String configEdn,
    String txData, {
    DatahikeFormat txFormat = DatahikeFormat.edn,
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.transact(
      configEdn,
      txData,
      txFormat: txFormat,
      outputFormat: outputFormat,
    ),
  );

  DatahikeResult<String> q(
    String queryEdn,
    List<DatahikeInput> inputs, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => inputs.isEmpty
      ? left(
          const DatahikeInvalidInputFailure('q requires at least one input.'),
        )
      : _capture(() => _raw.q(queryEdn, inputs, outputFormat: outputFormat));

  /// Alias for [q] that makes it explicit you are getting raw EDN.
  DatahikeResult<String> qRaw(
    String queryEdn,
    List<DatahikeInput> inputs, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => q(queryEdn, inputs, outputFormat: outputFormat);

  /// Executes a Datalog query and parses the result into rows.
  ///
  /// Returns `Either<DatahikeFailure, List<List<Object?>>>`.
  /// Throws [DatahikeException] if the EDN cannot be parsed.
  DatahikeResult<List<List<Object?>>> qRows(
    String queryEdn,
    List<DatahikeInput> inputs, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => q(queryEdn, inputs, outputFormat: outputFormat).map((edn) {
    final parsed = parseEdn(edn);
    if (parsed == null) return <List<Object?>>[];
    if (parsed is Set) {
      return parsed
          .map((row) => (row as List).cast<Object?>().toList())
          .toList();
    }
    if (parsed is List) {
      return parsed
          .map((row) => (row as List).cast<Object?>().toList())
          .toList();
    }
    throw DatahikeException(
      'Unexpected query result shape: ${parsed.runtimeType}',
    );
  });

  /// Executes a recursive pull query for entity [eid] using [selectorEdn].
  ///
  /// Returns the result as a raw EDN string. Use [pullMap] to get a parsed
  /// Dart map.
  ///
  /// ```dart
  /// final result = datahike.pull(
  ///   DatahikeInput.database(config),
  ///   '[:person/name :person/age]',
  ///   1,
  /// );
  /// ```
  DatahikeResult<String> pull(
    DatahikeInput input,
    String selectorEdn,
    int eid, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.pull(input, selectorEdn, eid, outputFormat: outputFormat),
  );

  /// Pulls multiple entities matching [eidsEdn] using [selectorEdn].
  ///
  /// [eidsEdn] is an EDN vector of entity ids, e.g. `[1 2 3]`.
  ///
  /// Returns the result as a raw EDN string.
  DatahikeResult<String> pullMany(
    DatahikeInput input,
    String selectorEdn,
    String eidsEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () =>
        _raw.pullMany(input, selectorEdn, eidsEdn, outputFormat: outputFormat),
  );

  /// Returns a raw EDN representation of entity [eid].
  ///
  /// Use [entityMap] to get the result as a parsed Dart map.
  /// Returns the full entity map for the given entity id.
  DatahikeResult<String> entity(
    DatahikeInput input,
    int eid, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.entity(input, eid, outputFormat: outputFormat));

  /// Pulls an entity and parses the result into a Dart map.
  ///
  /// Returns `null` when the entity does not exist (Datahike returns `nil`).
  DatahikeResult<Map<Object?, Object?>?> pullMap(
    DatahikeInput input,
    String selectorEdn,
    int eid, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => pull(input, selectorEdn, eid, outputFormat: outputFormat).map((edn) {
    final parsed = parseEdn(edn);
    if (parsed == null) return null;
    return (parsed as Map).cast<Object?, Object?>();
  });

  /// Returns an entity map for [eid], or `null` if the entity does not exist.
  DatahikeResult<Map<Object?, Object?>?> entityMap(
    DatahikeInput input,
    int eid, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => entity(input, eid, outputFormat: outputFormat).map((edn) {
    final parsed = parseEdn(edn);
    if (parsed == null) return null;
    return (parsed as Map).cast<Object?, Object?>();
  });

  /// Returns datoms parsed into a list of rows.
  ///
  /// Use [Datom.fromRow] to convert each row to a typed [Datom] object.
  ///
  /// ```dart
  /// final result = datahike.datomsList(
  ///   DatahikeInput.database(config),
  ///   ':eavt',
  /// );
  /// ```
  DatahikeResult<List<List<Object?>>> datomsList(
    DatahikeInput input,
    String indexEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => datoms(input, indexEdn, outputFormat: outputFormat).map((edn) {
    final parsed = parseEdn(edn);
    if (parsed == null) return <List<Object?>>[];
    return (parsed as List)
        .map((row) => (row as List).cast<Object?>().toList())
        .toList();
  });

  /// Returns database metrics as raw EDN (entity count, attribute count, etc.).
  DatahikeResult<String> metrics(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.metrics(input, outputFormat: outputFormat));

  /// Returns the current schema definition as raw EDN.
  ///
  /// The schema maps attribute keywords to their type/cardinality definitions.
  DatahikeResult<String> schema(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.schema(input, outputFormat: outputFormat));

  /// Returns the reverse schema — attribute keywords indexed by type.
  DatahikeResult<String> reverseSchema(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.reverseSchema(input, outputFormat: outputFormat));

  /// Returns the parent commit IDs for the database value.
  ///
  /// Useful for traversing the commit graph.
  DatahikeResult<String> parentCommitIds(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.parentCommitIds(input, outputFormat: outputFormat));

  /// Returns the commit ID of the current database value.
  DatahikeResult<String> commitId(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.commitId(input, outputFormat: outputFormat));

  /// Returns datoms for the given index (e.g. `:eavt`, `:avet`).
  ///
  /// Use [datomsList] to get parsed rows, or [Datom.fromRow] for typed datoms.
  DatahikeResult<String> datoms(
    DatahikeInput input,
    String indexEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) =>
      _capture(() => _raw.datoms(input, indexEdn, outputFormat: outputFormat));

  /// Returns datoms from [indexEdn] onward (seek into an index).
  DatahikeResult<String> seekDatoms(
    DatahikeInput input,
    String indexEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.seekDatoms(input, indexEdn, outputFormat: outputFormat),
  );

  /// Returns a range of the `:avet` index between [startEdn] and [endEdn].
  ///
  /// Useful for scanning attributes by value range.
  ///
  /// ```dart
  /// final result = datahike.indexRange(
  ///   DatahikeInput.database(config),
  ///   ':name',
  ///   '"A"',
  ///   '"Z"',
  /// );
  /// ```
  DatahikeResult<String> indexRange(
    DatahikeInput input,
    String attridEdn,
    String startEdn,
    String endEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.indexRange(
      input,
      attridEdn,
      startEdn,
      endEdn,
      outputFormat: outputFormat,
    ),
  );

  /// Invokes storage garbage collection, removing data before [beforeTx].
  ///
  /// **Destructive operation.** Removes historical data older than the given
  /// transaction timestamp. Use with caution.
  DatahikeResult<String> gcStorage(
    String configEdn,
    DateTime beforeTx, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.gcStorage(configEdn, beforeTx, outputFormat: outputFormat),
  );

  /// Lists all branch names for the database as raw EDN.
  DatahikeResult<String> branches(
    String configEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.branches(configEdn, outputFormat: outputFormat));

  /// Deletes the branch identified by [branchKeywordEdn] (e.g. `:experiment`).
  DatahikeResult<String> deleteBranch(
    String configEdn,
    String branchKeywordEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.deleteBranch(
      configEdn,
      branchKeywordEdn,
      outputFormat: outputFormat,
    ),
  );

  /// Creates a new branch from an existing commit or branch.
  ///
  /// [fromEdn] is an EDN branch keyword (e.g. `:main`) or a commit UUID.
  /// [newBranchKeywordEdn] is the name for the new branch (e.g. `:experiment`).
  ///
  /// ```dart
  /// final result = datahike.branch(config, ':main', ':experiment');
  /// ```
  DatahikeResult<String> branch(
    String configEdn,
    String fromEdn,
    String newBranchKeywordEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.branch(
      configEdn,
      fromEdn,
      newBranchKeywordEdn,
      outputFormat: outputFormat,
    ),
  );

  /// Merges [parentsEdn] with transaction data into the database.
  ///
  /// [parentsEdn] is an EDN vector of parent commits or branch keywords.
  /// This is a multi-parent merge operation for combining divergent histories.
  DatahikeResult<String> mergeDb(
    String configEdn,
    String parentsEdn,
    String txData, {
    DatahikeFormat txFormat = DatahikeFormat.edn,
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.mergeDb(
      configEdn,
      parentsEdn,
      txData,
      txFormat: txFormat,
      outputFormat: outputFormat,
    ),
  );

  DatahikeResult<T> _capture<T>(T Function() run) => Either.tryCatch(
    run,
    (error, _) => switch (error) {
      StateError(:final message) => DatahikeClosedFailure(message, error),
      DatahikeException(:final message) => DatahikeNativeFailure(
        message,
        error,
      ),
      ArgumentError(:final message) => DatahikeInvalidInputFailure(
        message?.toString() ?? 'Invalid Datahike input.',
        error,
      ),
      _ => DatahikeNativeFailure(error.toString(), error),
    },
  );
}

/// Raw FFI client for Datahike's native library.
///
/// Each operation opens/connects through the native API using a config EDN
/// string. The native API returns results via callbacks; this wrapper presents
/// synchronous Dart methods returning strings in [outputFormat].
final class Datahike {
  Datahike._(this._bindings, this._library);

  /// Opens Datahike's native library.
  ///
  /// Resolution order:
  /// 1. explicit [libraryPath]
  /// 2. `DATAHIKE_LIB` environment variable
  /// 3. app-local conventional paths (e.g. `.native/` under the current
  ///    working directory)
  /// 4. platform default name (`libdatahike.so`, `libdatahike.dylib`, or
  ///    `datahike.dll`) from the dynamic loader path
  factory Datahike.openRaw({String? libraryPath}) {
    try {
      final library = DatahikeNativeLibrary.open(libraryPath: libraryPath);
      return Datahike._(_DatahikeBindings(library), library);
    } on DatahikeLibraryException catch (e) {
      throw DatahikeException(e.message);
    }
  }

  final _DatahikeBindings _bindings;

  // Keep a reference so the dynamic library is not garbage-collected while the
  // bindings are in use.
  // ignore: unused_field
  final DynamicLibrary _library;

  var _closed = false;

  /// Releases the GraalVM isolate associated with this client.
  void close() {
    if (_closed) return;
    _bindings.close();
    _closed = true;
  }

  /// Creates a database from a Datahike config EDN map.
  String createDatabase(
    String configEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) =>
        _bindings.createDatabase(configEdn, outputFormat.nativeName, reader),
  );

  /// Deletes a database from a Datahike config EDN map.
  String deleteDatabase(
    String configEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) =>
        _bindings.deleteDatabase(configEdn, outputFormat.nativeName, reader),
  );

  /// Returns whether a database exists for [configEdn].
  bool databaseExists(String configEdn) {
    final result = _call(
      (reader) => _bindings.databaseExists(
        configEdn,
        DatahikeFormat.edn.nativeName,
        reader,
      ),
    );
    return result.trim() == 'true';
  }

  /// Applies transaction data to the database.
  String transact(
    String configEdn,
    String txData, {
    DatahikeFormat txFormat = DatahikeFormat.edn,
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.transact(
      configEdn,
      txFormat.nativeName,
      txData,
      outputFormat.nativeName,
      reader,
    ),
  );

  /// Executes a Datalog query.
  String q(
    String queryEdn,
    List<DatahikeInput> inputs, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.q(queryEdn, inputs, outputFormat.nativeName, reader),
  );

  /// Fetches data using a recursive pull selector.
  String pull(
    DatahikeInput input,
    String selectorEdn,
    int eid, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.pull(
      input.format,
      input.value,
      selectorEdn,
      eid,
      outputFormat.nativeName,
      reader,
    ),
  );

  /// Pulls multiple entities.
  String pullMany(
    DatahikeInput input,
    String selectorEdn,
    String eidsEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.pullMany(
      input.format,
      input.value,
      selectorEdn,
      eidsEdn,
      outputFormat.nativeName,
      reader,
    ),
  );

  /// Returns an entity map for [eid].
  String entity(
    DatahikeInput input,
    int eid, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.entity(
      input.format,
      input.value,
      eid,
      outputFormat.nativeName,
      reader,
    ),
  );

  /// Returns database metrics.
  String metrics(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _readInput(_bindings.metrics, input, outputFormat);

  /// Returns current schema definition.
  String schema(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _readInput(_bindings.schema, input, outputFormat);

  /// Returns reverse schema definition.
  String reverseSchema(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _readInput(_bindings.reverseSchema, input, outputFormat);

  /// Returns parent commit ids for the input database value.
  String parentCommitIds(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _readInput(_bindings.parentCommitIds, input, outputFormat);

  /// Returns the commit id for the input database value.
  String commitId(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _readInput(_bindings.commitId, input, outputFormat);

  /// Returns datoms for an index keyword EDN, e.g. `:eavt`.
  String datoms(
    DatahikeInput input,
    String indexEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.datoms(
      input.format,
      input.value,
      indexEdn,
      outputFormat.nativeName,
      reader,
    ),
  );

  /// Returns datoms from [indexEdn] onward.
  String seekDatoms(
    DatahikeInput input,
    String indexEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.seekDatoms(
      input.format,
      input.value,
      indexEdn,
      outputFormat.nativeName,
      reader,
    ),
  );

  /// Returns part of `:avet` index between [startEdn] and [endEdn].
  String indexRange(
    DatahikeInput input,
    String attridEdn,
    String startEdn,
    String endEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.indexRange(
      input.format,
      input.value,
      attridEdn,
      startEdn,
      endEdn,
      outputFormat.nativeName,
      reader,
    ),
  );

  /// Invokes Datahike storage garbage collection.
  String gcStorage(
    String configEdn,
    DateTime beforeTx, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.gcStorage(
      configEdn,
      beforeTx.millisecondsSinceEpoch,
      outputFormat.nativeName,
      reader,
    ),
  );

  /// Lists all branch names.
  String branches(
    String configEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.branches(configEdn, outputFormat.nativeName, reader),
  );

  /// Deletes [branchKeywordEdn], e.g. `:experiment`.
  String deleteBranch(
    String configEdn,
    String branchKeywordEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.deleteBranch(
      configEdn,
      branchKeywordEdn,
      outputFormat.nativeName,
      reader,
    ),
  );

  /// Creates a branch from an EDN branch keyword or UUID.
  String branch(
    String configEdn,
    String fromEdn,
    String newBranchKeywordEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.branch(
      configEdn,
      fromEdn,
      newBranchKeywordEdn,
      outputFormat.nativeName,
      reader,
    ),
  );

  /// Merges [parentsEdn] with transaction data.
  String mergeDb(
    String configEdn,
    String parentsEdn,
    String txData, {
    DatahikeFormat txFormat = DatahikeFormat.edn,
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _call(
    (reader) => _bindings.mergeDb(
      configEdn,
      parentsEdn,
      txFormat.nativeName,
      txData,
      outputFormat.nativeName,
      reader,
    ),
  );

  String _readInput(
    void Function(String, String, String, _OutputReaderNative) function,
    DatahikeInput input,
    DatahikeFormat outputFormat,
  ) => _call(
    (reader) =>
        function(input.format, input.value, outputFormat.nativeName, reader),
  );

  String _call(void Function(_OutputReaderNative reader) invoke) {
    if (_closed) {
      throw StateError('Datahike client is closed.');
    }
    final callback = _CallbackCapture();
    try {
      invoke(callback.nativeReader);
      final output = callback.output;
      if (output == null) {
        throw const DatahikeException('Native call did not return a value.');
      }
      if (output.startsWith('exception:')) {
        throw DatahikeException(output.substring('exception:'.length));
      }
      return output;
    } finally {
      callback.dispose();
    }
  }
}

typedef _OutputReaderNative =
    Pointer<NativeFunction<Void Function(Pointer<Utf8>)>>;
typedef _OutputReaderDart = Void Function(Pointer<Utf8>);

final class _CallbackCapture {
  String? output;

  late final _nativeCallable = NativeCallable<_OutputReaderDart>.isolateLocal((
    Pointer<Utf8> ptr,
  ) {
    output = ptr.toDartString();
  });

  _OutputReaderNative get nativeReader => _nativeCallable.nativeFunction;

  void dispose() {
    _nativeCallable.close();
  }
}

typedef _GraalCreateIsolateNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Pointer<Void>>,
      Pointer<Pointer<Void>>,
    );
typedef _GraalCreateIsolateDart =
    int Function(Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Pointer<Void>>);

typedef _GraalDetachThreadNative = Int32 Function(Pointer<Void>);
typedef _GraalDetachThreadDart = int Function(Pointer<Void>);

typedef _DbConfigOutputNative =
    Void Function(Int64, Pointer<Utf8>, Pointer<Utf8>, _OutputReaderNative);
typedef _DbConfigOutputDart =
    void Function(int, Pointer<Utf8>, Pointer<Utf8>, _OutputReaderNative);

typedef _ReadInputNative =
    Void Function(
      Int64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );
typedef _ReadInputDart =
    void Function(
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );

typedef _TransactNative =
    Void Function(
      Int64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );
typedef _TransactDart =
    void Function(
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );

typedef _QueryNative =
    Void Function(
      Int64,
      Pointer<Utf8>,
      Int64,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );
typedef _QueryDart =
    void Function(
      int,
      Pointer<Utf8>,
      int,
      Pointer<Pointer<Utf8>>,
      Pointer<Pointer<Utf8>>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );

typedef _PullNative =
    Void Function(
      Int64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int64,
      Pointer<Utf8>,
      _OutputReaderNative,
    );
typedef _PullDart =
    void Function(
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      Pointer<Utf8>,
      _OutputReaderNative,
    );

typedef _PullManyNative =
    Void Function(
      Int64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );
typedef _PullManyDart =
    void Function(
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );

typedef _EntityNative =
    Void Function(
      Int64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Int64,
      Pointer<Utf8>,
      _OutputReaderNative,
    );
typedef _EntityDart =
    void Function(
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      int,
      Pointer<Utf8>,
      _OutputReaderNative,
    );

typedef _DatomsNative =
    Void Function(
      Int64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );
typedef _DatomsDart =
    void Function(
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );

typedef _IndexRangeNative =
    Void Function(
      Int64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );
typedef _IndexRangeDart =
    void Function(
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );

typedef _GcStorageNative =
    Void Function(
      Int64,
      Pointer<Utf8>,
      Int64,
      Pointer<Utf8>,
      _OutputReaderNative,
    );
typedef _GcStorageDart =
    void Function(int, Pointer<Utf8>, int, Pointer<Utf8>, _OutputReaderNative);

typedef _DeleteBranchNative =
    Void Function(
      Int64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );
typedef _DeleteBranchDart =
    void Function(
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );

typedef _BranchNative =
    Void Function(
      Int64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );
typedef _BranchDart =
    void Function(
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );

typedef _MergeDbNative =
    Void Function(
      Int64,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );
typedef _MergeDbDart =
    void Function(
      int,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      _OutputReaderNative,
    );

final class _DatahikeBindings {
  _DatahikeBindings(DynamicLibrary library)
    : _graalDetachThread = library
          .lookupFunction<_GraalDetachThreadNative, _GraalDetachThreadDart>(
            'graal_detach_thread',
          ),
      _deleteDatabase = library
          .lookupFunction<_DbConfigOutputNative, _DbConfigOutputDart>(
            'delete_database',
          ),
      _createDatabase = library
          .lookupFunction<_DbConfigOutputNative, _DbConfigOutputDart>(
            'create_database',
          ),
      _databaseExists = library
          .lookupFunction<_DbConfigOutputNative, _DbConfigOutputDart>(
            'database_exists',
          ),
      _transact = library.lookupFunction<_TransactNative, _TransactDart>(
        'transact',
      ),
      _q = library.lookupFunction<_QueryNative, _QueryDart>('q'),
      _pull = library.lookupFunction<_PullNative, _PullDart>('pull'),
      _entity = library.lookupFunction<_EntityNative, _EntityDart>('entity'),
      _metrics = library.lookupFunction<_ReadInputNative, _ReadInputDart>(
        'metrics',
      ),
      _reverseSchema = library.lookupFunction<_ReadInputNative, _ReadInputDart>(
        'reverse_schema',
      ),
      _datoms = library.lookupFunction<_DatomsNative, _DatomsDart>('datoms'),
      _schema = library.lookupFunction<_ReadInputNative, _ReadInputDart>(
        'schema',
      ),
      _indexRange = library.lookupFunction<_IndexRangeNative, _IndexRangeDart>(
        'index_range',
      ),
      _pullMany = library.lookupFunction<_PullManyNative, _PullManyDart>(
        'pull_many',
      ),
      _gcStorage = library.lookupFunction<_GcStorageNative, _GcStorageDart>(
        'gc_storage',
      ),
      _parentCommitIds = library
          .lookupFunction<_ReadInputNative, _ReadInputDart>(
            'parent_commit_ids',
          ),
      _branches = library
          .lookupFunction<_DbConfigOutputNative, _DbConfigOutputDart>(
            'branches',
          ),
      _deleteBranch = library
          .lookupFunction<_DeleteBranchNative, _DeleteBranchDart>(
            'delete_branch',
          ),
      _mergeDb = library.lookupFunction<_MergeDbNative, _MergeDbDart>(
        'merge_db',
      ),
      _seekDatoms = library.lookupFunction<_DatomsNative, _DatomsDart>(
        'seek_datoms',
      ),
      _commitId = library.lookupFunction<_ReadInputNative, _ReadInputDart>(
        'commit_id',
      ),
      _branch = library.lookupFunction<_BranchNative, _BranchDart>('branch') {
    final createIsolate = library
        .lookupFunction<_GraalCreateIsolateNative, _GraalCreateIsolateDart>(
          'graal_create_isolate',
        );
    final isolatePtr = calloc<Pointer<Void>>();
    final threadPtr = calloc<Pointer<Void>>();
    try {
      final result = createIsolate(nullptr, isolatePtr, threadPtr);
      if (result != 0) {
        throw DatahikeException(
          'graal_create_isolate failed with code $result',
        );
      }
      _thread = threadPtr.value;
      _threadAddress = _thread.address;
    } finally {
      calloc.free(isolatePtr);
      calloc.free(threadPtr);
    }
  }

  final _GraalDetachThreadDart _graalDetachThread;
  final _DbConfigOutputDart _deleteDatabase;
  final _PullDart _pull;
  final _EntityDart _entity;
  final _ReadInputDart _metrics;
  final _ReadInputDart _reverseSchema;
  final _DatomsDart _datoms;
  final _QueryDart _q;
  final _ReadInputDart _schema;
  final _IndexRangeDart _indexRange;
  final _PullManyDart _pullMany;
  final _GcStorageDart _gcStorage;
  final _DbConfigOutputDart _createDatabase;
  final _ReadInputDart _parentCommitIds;
  final _DbConfigOutputDart _branches;
  final _DeleteBranchDart _deleteBranch;
  final _DbConfigOutputDart _databaseExists;
  final _TransactDart _transact;
  final _MergeDbDart _mergeDb;
  final _DatomsDart _seekDatoms;
  final _ReadInputDart _commitId;
  final _BranchDart _branch;

  late final Pointer<Void> _thread;
  late final int _threadAddress;

  void close() {
    _graalDetachThread(_thread);
  }

  void createDatabase(
    String configEdn,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([configEdn, outputFormat], (p) {
    _createDatabase(_threadAddress, p[0], p[1], reader);
  });

  void deleteDatabase(
    String configEdn,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([configEdn, outputFormat], (p) {
    _deleteDatabase(_threadAddress, p[0], p[1], reader);
  });

  void databaseExists(
    String configEdn,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([configEdn, outputFormat], (p) {
    _databaseExists(_threadAddress, p[0], p[1], reader);
  });

  void transact(
    String configEdn,
    String txFormat,
    String txData,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([configEdn, txFormat, txData, outputFormat], (p) {
    _transact(_threadAddress, p[0], p[1], p[2], p[3], reader);
  });

  void q(
    String queryEdn,
    List<DatahikeInput> inputs,
    String outputFormat,
    _OutputReaderNative reader,
  ) {
    final queryPtr = queryEdn.toNativeUtf8();
    final outputFormatPtr = outputFormat.toNativeUtf8();
    final formatPointers = <Pointer<Utf8>>[];
    final valuePointers = <Pointer<Utf8>>[];
    final nativeFormats = calloc<Pointer<Utf8>>(inputs.length);
    final nativeValues = calloc<Pointer<Utf8>>(inputs.length);

    try {
      for (var i = 0; i < inputs.length; i++) {
        final formatPtr = inputs[i].format.toNativeUtf8();
        final valuePtr = inputs[i].value.toNativeUtf8();
        formatPointers.add(formatPtr);
        valuePointers.add(valuePtr);
        nativeFormats[i] = formatPtr;
        nativeValues[i] = valuePtr;
      }
      _q(
        _threadAddress,
        queryPtr,
        inputs.length,
        nativeFormats,
        nativeValues,
        outputFormatPtr,
        reader,
      );
    } finally {
      calloc.free(queryPtr);
      calloc.free(outputFormatPtr);
      for (final pointer in formatPointers) {
        calloc.free(pointer);
      }
      for (final pointer in valuePointers) {
        calloc.free(pointer);
      }
      calloc.free(nativeFormats);
      calloc.free(nativeValues);
    }
  }

  void pull(
    String inputFormat,
    String rawInput,
    String selectorEdn,
    int eid,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([inputFormat, rawInput, selectorEdn, outputFormat], (p) {
    _pull(_threadAddress, p[0], p[1], p[2], eid, p[3], reader);
  });

  void pullMany(
    String inputFormat,
    String rawInput,
    String selectorEdn,
    String eidsEdn,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([inputFormat, rawInput, selectorEdn, eidsEdn, outputFormat], (
    p,
  ) {
    _pullMany(_threadAddress, p[0], p[1], p[2], p[3], p[4], reader);
  });

  void entity(
    String inputFormat,
    String rawInput,
    int eid,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([inputFormat, rawInput, outputFormat], (p) {
    _entity(_threadAddress, p[0], p[1], eid, p[2], reader);
  });

  void metrics(
    String inputFormat,
    String rawInput,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _readInput(_metrics, inputFormat, rawInput, outputFormat, reader);

  void reverseSchema(
    String inputFormat,
    String rawInput,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _readInput(_reverseSchema, inputFormat, rawInput, outputFormat, reader);

  void schema(
    String inputFormat,
    String rawInput,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _readInput(_schema, inputFormat, rawInput, outputFormat, reader);

  void parentCommitIds(
    String inputFormat,
    String rawInput,
    String outputFormat,
    _OutputReaderNative reader,
  ) =>
      _readInput(_parentCommitIds, inputFormat, rawInput, outputFormat, reader);

  void commitId(
    String inputFormat,
    String rawInput,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _readInput(_commitId, inputFormat, rawInput, outputFormat, reader);

  void datoms(
    String inputFormat,
    String rawInput,
    String indexEdn,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([inputFormat, rawInput, indexEdn, outputFormat], (p) {
    _datoms(_threadAddress, p[0], p[1], p[2], p[3], reader);
  });

  void seekDatoms(
    String inputFormat,
    String rawInput,
    String indexEdn,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([inputFormat, rawInput, indexEdn, outputFormat], (p) {
    _seekDatoms(_threadAddress, p[0], p[1], p[2], p[3], reader);
  });

  void indexRange(
    String inputFormat,
    String rawInput,
    String attridEdn,
    String startEdn,
    String endEdn,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8(
    [inputFormat, rawInput, attridEdn, startEdn, endEdn, outputFormat],
    (p) {
      _indexRange(_threadAddress, p[0], p[1], p[2], p[3], p[4], p[5], reader);
    },
  );

  void gcStorage(
    String configEdn,
    int beforeTxUnixTimeMs,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([configEdn, outputFormat], (p) {
    _gcStorage(_threadAddress, p[0], beforeTxUnixTimeMs, p[1], reader);
  });

  void branches(
    String configEdn,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([configEdn, outputFormat], (p) {
    _branches(_threadAddress, p[0], p[1], reader);
  });

  void deleteBranch(
    String configEdn,
    String branchKeywordEdn,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([configEdn, branchKeywordEdn, outputFormat], (p) {
    _deleteBranch(_threadAddress, p[0], p[1], p[2], reader);
  });

  void branch(
    String configEdn,
    String fromEdn,
    String newBranchKeywordEdn,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([configEdn, fromEdn, newBranchKeywordEdn, outputFormat], (p) {
    _branch(_threadAddress, p[0], p[1], p[2], p[3], reader);
  });

  void mergeDb(
    String configEdn,
    String parentsEdn,
    String txFormat,
    String txData,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([configEdn, parentsEdn, txFormat, txData, outputFormat], (p) {
    _mergeDb(_threadAddress, p[0], p[1], p[2], p[3], p[4], reader);
  });

  void _readInput(
    _ReadInputDart function,
    String inputFormat,
    String rawInput,
    String outputFormat,
    _OutputReaderNative reader,
  ) => _withUtf8([inputFormat, rawInput, outputFormat], (p) {
    function(_threadAddress, p[0], p[1], p[2], reader);
  });

  void _withUtf8(List<String> values, void Function(List<Pointer<Utf8>>) fn) {
    final pointers = values.map((value) => value.toNativeUtf8()).toList();
    try {
      fn(pointers);
    } finally {
      for (final pointer in pointers) {
        calloc.free(pointer);
      }
    }
  }
}

String _bareKeywordName(String value) =>
    value.startsWith(':') ? value.substring(1) : value;

/// A single Datahike datom: `[e a v t]` or `[e a v t added?]`.
///
/// A datom is the atomic unit of Datahike's data model. Each datom
/// represents one fact: entity [e] has attribute [a] with value [v]
/// at transaction [t].
///
/// Created by parsing the EDN rows returned from [DatahikeClient.datomsList].
///
/// ```dart
/// final result = datahike.datomsList(
///   DatahikeInput.database(config),
///   ':eavt',
/// );
/// result.match(
///   (failure) => print('Error: $failure'),
///   (rows) => rows.map(Datom.fromRow).forEach(print),
/// );
/// ```
final class Datom {
  const Datom({
    required this.e,
    required this.a,
    required this.v,
    required this.t,
    this.added,
  });

  /// Entity id.
  final int e;

  /// Attribute keyword, e.g. `:name`.
  final String a;

  /// Value.
  final Object? v;

  /// Transaction id or transaction time.
  final Object? t;

  /// Whether this datom was added (`true`) or retracted (`false`).
  final bool? added;

  /// Parses an EDN datom row into a typed [Datom].
  ///
  /// ```dart
  /// final datom = Datom.fromRow([1, ':name', 'Alice', 1001, true]);
  /// print(datom.e);    // 1
  /// print(datom.a);    // ':name'
  /// print(datom.v);    // 'Alice'
  /// print(datom.added); // true
  /// ```
  factory Datom.fromRow(List<Object?> row) {
    return Datom(
      e: row[0] as int,
      a: row[1] as String,
      v: row[2],
      t: row[3],
      added: row.length > 4 ? row[4] as bool? : null,
    );
  }

  @override
  String toString() =>
      'Datom(e: $e, a: $a, v: $v, t: $t${added != null ? ', added: $added' : ''})';

  @override
  bool operator ==(Object other) =>
      other is Datom &&
      other.e == e &&
      other.a == a &&
      other.v == v &&
      other.t == t &&
      other.added == added;

  @override
  int get hashCode => Object.hash(e, a, v, t, added);
}
