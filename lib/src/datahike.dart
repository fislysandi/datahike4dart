import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:fpdart/fpdart.dart';

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
  const DatahikeInput.history(String configEdn) : this('history', configEdn);

  /// Load the database as of [timestamp].
  ///
  /// Returns an input that represents the database state at the given timestamp.
  factory DatahikeInput.asOf(String configEdn, DateTime timestamp) =>
      DatahikeInput('asof:${timestamp.millisecondsSinceEpoch}', configEdn);

  /// Load the database since [timestamp].
  ///
  /// Returns an input that represents the database state after the given timestamp.
  factory DatahikeInput.since(String configEdn, DateTime timestamp) =>
      DatahikeInput('since:${timestamp.millisecondsSinceEpoch}', configEdn);

  /// Load the database at a named branch.
  ///
  /// Returns an input that represents the database at the specified branch.
  factory DatahikeInput.branch(String configEdn, String branchName) =>
      DatahikeInput('branch:${_bareKeywordName(branchName)}', configEdn);

  /// Load the database at a commit UUID.
  ///
  /// Returns an input that represents the database at the specified commit.
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
sealed class DatahikeFailure {
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
final class DatahikeException implements Exception {
  const DatahikeException(this.message);

  final String message;

  @override
  String toString() => 'DatahikeException: $message';
}

/// Functional result type used by the public API.
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
          'Failed to load or initialize Datahike native library.',
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

  DatahikeResult<String> pull(
    DatahikeInput input,
    String selectorEdn,
    int eid, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.pull(input, selectorEdn, eid, outputFormat: outputFormat),
  );

  DatahikeResult<String> pullMany(
    DatahikeInput input,
    String selectorEdn,
    String eidsEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () =>
        _raw.pullMany(input, selectorEdn, eidsEdn, outputFormat: outputFormat),
  );

  DatahikeResult<String> entity(
    DatahikeInput input,
    int eid, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.entity(input, eid, outputFormat: outputFormat));

  DatahikeResult<String> metrics(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.metrics(input, outputFormat: outputFormat));

  DatahikeResult<String> schema(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.schema(input, outputFormat: outputFormat));

  DatahikeResult<String> reverseSchema(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.reverseSchema(input, outputFormat: outputFormat));

  DatahikeResult<String> parentCommitIds(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.parentCommitIds(input, outputFormat: outputFormat));

  DatahikeResult<String> commitId(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.commitId(input, outputFormat: outputFormat));

  DatahikeResult<String> datoms(
    DatahikeInput input,
    String indexEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) =>
      _capture(() => _raw.datoms(input, indexEdn, outputFormat: outputFormat));

  DatahikeResult<String> seekDatoms(
    DatahikeInput input,
    String indexEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.seekDatoms(input, indexEdn, outputFormat: outputFormat),
  );

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

  DatahikeResult<String> gcStorage(
    String configEdn,
    DateTime beforeTx, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(
    () => _raw.gcStorage(configEdn, beforeTx, outputFormat: outputFormat),
  );

  DatahikeResult<String> branches(
    String configEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _capture(() => _raw.branches(configEdn, outputFormat: outputFormat));

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
  /// 3. platform default name (`libdatahike.so`, `libdatahike.dylib`, or
  ///    `datahike.dll`) from the dynamic loader path
  factory Datahike.openRaw({String? libraryPath}) {
    final path = libraryPath ?? Platform.environment['DATAHIKE_LIB'];
    final library = path == null || path.isEmpty
        ? DynamicLibrary.open(_defaultLibraryName())
        : DynamicLibrary.open(path);
    return Datahike._(_DatahikeBindings(library), library);
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
    invoke(callback.nativeReader);
    final output = callback.output;
    if (output == null) {
      throw const DatahikeException('Native call did not return a value.');
    }
    if (output.startsWith('exception:')) {
      throw DatahikeException(output.substring('exception:'.length));
    }
    return output;
  }
}

typedef _OutputReaderNative =
    Pointer<NativeFunction<Void Function(Pointer<Utf8>)>>;
typedef _OutputReaderDart = Void Function(Pointer<Utf8>);

final class _CallbackCapture {
  _CallbackCapture() {
    _active = this;
  }

  static _CallbackCapture? _active;

  String? output;

  _OutputReaderNative get nativeReader =>
      Pointer.fromFunction<_OutputReaderDart>(_readOutput);

  static void _readOutput(Pointer<Utf8> output) {
    _active?.output = output.toDartString();
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

String _defaultLibraryName() {
  if (Platform.isMacOS) return 'libdatahike.dylib';
  if (Platform.isWindows) return 'datahike.dll';
  return 'libdatahike.so';
}

String _bareKeywordName(String value) =>
    value.startsWith(':') ? value.substring(1) : value;
