/// Async FFI wrapper that runs Datahike in a dedicated worker isolate.
///
/// `DatahikeClient` instances contain `DynamicLibrary` and `NativeCallable`
/// references that are **not safe to share across isolates**. This service
/// creates the client inside the worker, keeps it alive, and exposes every
/// public operation as an async method that does not block the calling isolate.
///
/// ```dart
/// final service = await DatahikeIsolate.start();
/// final result = await service.q('[:find ?e ...]', [DatahikeInput.database(config)]);
/// await service.close();
/// ```
library;

import 'dart:async';
import 'dart:isolate';

import 'package:fpdart/fpdart.dart';

import 'datahike.dart';

/// Failure type used when the isolate itself fails (not a Datahike native
/// failure). For example, the worker isolate crashing or a serialization error.
final class DatahikeIsolateFailure extends DatahikeFailure {
  const DatahikeIsolateFailure(super.message, [super.cause]);
}

/// Async wrapper around [DatahikeClient] that runs all operations in a worker
/// isolate.
final class DatahikeIsolate {
  DatahikeIsolate._(this._sendPort, this._receivePort, this._isolate);

  /// Spawns a worker isolate, loads the native library inside it, and returns
  /// a handle for async operations.
  static Future<DatahikeIsolate> start({String? libraryPath}) async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerEntry,
      _WorkerInit(receivePort.sendPort, libraryPath: libraryPath),
    );
    final sendPort = await receivePort.first as SendPort;
    return DatahikeIsolate._(sendPort, receivePort, isolate);
  }

  final SendPort _sendPort;
  final ReceivePort _receivePort;
  final Isolate _isolate;

  var _closed = false;

  /// Releases the worker isolate and closes the native client inside it.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _sendPort.send(const _ShutdownCommand());
    _receivePort.close();
    _isolate.kill();
  }

  /// Creates a database. Async version of [DatahikeClient.createDatabase].
  Future<DatahikeResult<String>> createDatabase(
    String configEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('createDatabase', {
    'configEdn': configEdn,
    'outputFormat': outputFormat.nativeName,
  });

  /// Deletes a database. Async version of [DatahikeClient.deleteDatabase].
  Future<DatahikeResult<String>> deleteDatabase(
    String configEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('deleteDatabase', {
    'configEdn': configEdn,
    'outputFormat': outputFormat.nativeName,
  });

  /// Checks if a database exists. Async version of [DatahikeClient.databaseExists].
  Future<DatahikeResult<bool>> databaseExists(String configEdn) =>
      _invoke('databaseExists', {'configEdn': configEdn});

  /// Transacts data into the database. Async version of [DatahikeClient.transact].
  Future<DatahikeResult<String>> transact(
    String configEdn,
    String txData, {
    DatahikeFormat txFormat = DatahikeFormat.edn,
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('transact', {
    'configEdn': configEdn,
    'txData': txData,
    'txFormat': txFormat.nativeName,
    'outputFormat': outputFormat.nativeName,
  });

  /// Executes a Datalog query. Async version of [DatahikeClient.q].
  Future<DatahikeResult<String>> q(
    String queryEdn,
    List<DatahikeInput> inputs, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => inputs.isEmpty
      ? Future.value(
          left(
            const DatahikeInvalidInputFailure('q requires at least one input.'),
          ),
        )
      : _invoke('q', {
          'queryEdn': queryEdn,
          'inputs': inputs
              .map((i) => {'format': i.format, 'value': i.value})
              .toList(),
          'outputFormat': outputFormat.nativeName,
        });

  /// Pulls an entity by selector. Async version of [DatahikeClient.pull].
  Future<DatahikeResult<String>> pull(
    DatahikeInput input,
    String selectorEdn,
    int eid, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('pull', {
    'inputFormat': input.format,
    'inputValue': input.value,
    'selectorEdn': selectorEdn,
    'eid': eid,
    'outputFormat': outputFormat.nativeName,
  });

  /// Pulls multiple entities. Async version of [DatahikeClient.pullMany].
  Future<DatahikeResult<String>> pullMany(
    DatahikeInput input,
    String selectorEdn,
    String eidsEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('pullMany', {
    'inputFormat': input.format,
    'inputValue': input.value,
    'selectorEdn': selectorEdn,
    'eidsEdn': eidsEdn,
    'outputFormat': outputFormat.nativeName,
  });

  /// Returns an entity map. Async version of [DatahikeClient.entity].
  Future<DatahikeResult<String>> entity(
    DatahikeInput input,
    int eid, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('entity', {
    'inputFormat': input.format,
    'inputValue': input.value,
    'eid': eid,
    'outputFormat': outputFormat.nativeName,
  });

  /// Returns datoms for an index. Async version of [DatahikeClient.datoms].
  Future<DatahikeResult<String>> datoms(
    DatahikeInput input,
    String indexEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('datoms', {
    'inputFormat': input.format,
    'inputValue': input.value,
    'indexEdn': indexEdn,
    'outputFormat': outputFormat.nativeName,
  });

  /// Seeks into an index. Async version of [DatahikeClient.seekDatoms].
  Future<DatahikeResult<String>> seekDatoms(
    DatahikeInput input,
    String indexEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('seekDatoms', {
    'inputFormat': input.format,
    'inputValue': input.value,
    'indexEdn': indexEdn,
    'outputFormat': outputFormat.nativeName,
  });

  /// Returns the schema. Async version of [DatahikeClient.schema].
  Future<DatahikeResult<String>> schema(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('schema', {
    'inputFormat': input.format,
    'inputValue': input.value,
    'outputFormat': outputFormat.nativeName,
  });

  /// Returns the reverse schema. Async version of [DatahikeClient.reverseSchema].
  Future<DatahikeResult<String>> reverseSchema(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('reverseSchema', {
    'inputFormat': input.format,
    'inputValue': input.value,
    'outputFormat': outputFormat.nativeName,
  });

  /// Returns database metrics. Async version of [DatahikeClient.metrics].
  Future<DatahikeResult<String>> metrics(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('metrics', {
    'inputFormat': input.format,
    'inputValue': input.value,
    'outputFormat': outputFormat.nativeName,
  });

  /// Lists branches. Async version of [DatahikeClient.branches].
  Future<DatahikeResult<String>> branches(
    String configEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('branches', {
    'configEdn': configEdn,
    'outputFormat': outputFormat.nativeName,
  });

  /// Creates a branch. Async version of [DatahikeClient.branch].
  Future<DatahikeResult<String>> branch(
    String configEdn,
    String fromEdn,
    String newBranchKeywordEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('branch', {
    'configEdn': configEdn,
    'fromEdn': fromEdn,
    'newBranchKeywordEdn': newBranchKeywordEdn,
    'outputFormat': outputFormat.nativeName,
  });

  /// Deletes a branch. Async version of [DatahikeClient.deleteBranch].
  Future<DatahikeResult<String>> deleteBranch(
    String configEdn,
    String branchKeywordEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('deleteBranch', {
    'configEdn': configEdn,
    'branchKeywordEdn': branchKeywordEdn,
    'outputFormat': outputFormat.nativeName,
  });

  /// Returns the commit ID. Async version of [DatahikeClient.commitId].
  Future<DatahikeResult<String>> commitId(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('commitId', {
    'inputFormat': input.format,
    'inputValue': input.value,
    'outputFormat': outputFormat.nativeName,
  });

  /// Returns parent commit IDs. Async version of [DatahikeClient.parentCommitIds].
  Future<DatahikeResult<String>> parentCommitIds(
    DatahikeInput input, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('parentCommitIds', {
    'inputFormat': input.format,
    'inputValue': input.value,
    'outputFormat': outputFormat.nativeName,
  });

  /// Returns an index range. Async version of [DatahikeClient.indexRange].
  Future<DatahikeResult<String>> indexRange(
    DatahikeInput input,
    String attridEdn,
    String startEdn,
    String endEdn, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('indexRange', {
    'inputFormat': input.format,
    'inputValue': input.value,
    'attridEdn': attridEdn,
    'startEdn': startEdn,
    'endEdn': endEdn,
    'outputFormat': outputFormat.nativeName,
  });

  /// Runs garbage collection. Async version of [DatahikeClient.gcStorage].
  Future<DatahikeResult<String>> gcStorage(
    String configEdn,
    DateTime beforeTx, {
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('gcStorage', {
    'configEdn': configEdn,
    'beforeTxMs': beforeTx.millisecondsSinceEpoch,
    'outputFormat': outputFormat.nativeName,
  });

  /// Merges databases. Async version of [DatahikeClient.mergeDb].
  Future<DatahikeResult<String>> mergeDb(
    String configEdn,
    String parentsEdn,
    String txData, {
    DatahikeFormat txFormat = DatahikeFormat.edn,
    DatahikeFormat outputFormat = DatahikeFormat.edn,
  }) => _invoke('mergeDb', {
    'configEdn': configEdn,
    'parentsEdn': parentsEdn,
    'txFormat': txFormat.nativeName,
    'txData': txData,
    'outputFormat': outputFormat.nativeName,
  });

  Future<DatahikeResult<T>> _invoke<T>(String cmd, Map<String, Object?> args) {
    if (_closed) {
      return Future.value(
        left(
          const DatahikeClosedFailure(
            'DatahikeIsolate client has been closed.',
          ),
        ),
      );
    }
    final responsePort = ReceivePort();
    _sendPort.send(_WorkerCommand(cmd, args, responsePort.sendPort));
    return responsePort.first
        .then<DatahikeResult<T>>((result) {
          responsePort.close();
          return switch (result) {
            {'success': final Object? value} => right(value as T),
            {'failure': final Object? f} => _deserializeFailure<T>(f as Map),
            _ => left(
              DatahikeIsolateFailure('Unexpected isolate response: $result'),
            ),
          };
        })
        .catchError((Object error) {
          responsePort.close();
          return left<DatahikeFailure, T>(
            DatahikeIsolateFailure(
              'Isolate communication error: $error',
              error,
            ),
          );
        });
  }

  DatahikeResult<T> _deserializeFailure<T>(Map<dynamic, dynamic> f) {
    final type = f['type'] as String;
    final message = f['message'] as String;
    return left(switch (type) {
      'DatahikeLoadFailure' => DatahikeLoadFailure(message),
      'DatahikeNativeFailure' => DatahikeNativeFailure(message),
      'DatahikeClosedFailure' => DatahikeClosedFailure(message),
      'DatahikeInvalidInputFailure' => DatahikeInvalidInputFailure(message),
      _ => DatahikeIsolateFailure(message),
    });
  }
}

// ---------------------------------------------------------------------------
// Worker isolate side
// ---------------------------------------------------------------------------

void _workerEntry(_WorkerInit init) {
  final port = ReceivePort();
  init.mainSendPort.send(port.sendPort);

  DatahikeResult<DatahikeClient> clientResult = DatahikeClient.open(
    libraryPath: init.libraryPath,
  );
  DatahikeClient? client;

  port.listen((message) {
    switch (message) {
      case _ShutdownCommand():
        client?.close();
        port.close();
        return;

      case _WorkerCommand(:final cmd, :final args, :final replyPort):
        if (client == null) {
          clientResult.match(
            (failure) {
              replyPort.send({'failure': _serializeFailure(failure)});
            },
            (c) {
              client = c;
              _execute(client!, cmd, args, replyPort);
            },
          );
        } else {
          _execute(client!, cmd, args, replyPort);
        }
    }
  });
}

void _execute(
  DatahikeClient client,
  String cmd,
  Map<String, Object?> args,
  SendPort replyPort,
) {
  try {
    final result = switch (cmd) {
      'createDatabase' => client.createDatabase(
        args['configEdn']! as String,
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'deleteDatabase' => client.deleteDatabase(
        args['configEdn']! as String,
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'databaseExists' => client.databaseExists(args['configEdn']! as String),
      'transact' => client.transact(
        args['configEdn']! as String,
        args['txData']! as String,
        txFormat: _format(args['txFormat'] as String?),
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'q' => client.q(
        args['queryEdn']! as String,
        (args['inputs']! as List)
            .map(
              (i) => DatahikeInput(
                (i as Map)['format']! as String,
                i['value']! as String,
              ),
            )
            .toList(),
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'pull' => client.pull(
        DatahikeInput(
          args['inputFormat']! as String,
          args['inputValue']! as String,
        ),
        args['selectorEdn']! as String,
        args['eid']! as int,
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'pullMany' => client.pullMany(
        DatahikeInput(
          args['inputFormat']! as String,
          args['inputValue']! as String,
        ),
        args['selectorEdn']! as String,
        args['eidsEdn']! as String,
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'entity' => client.entity(
        DatahikeInput(
          args['inputFormat']! as String,
          args['inputValue']! as String,
        ),
        args['eid']! as int,
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'datoms' => client.datoms(
        DatahikeInput(
          args['inputFormat']! as String,
          args['inputValue']! as String,
        ),
        args['indexEdn']! as String,
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'seekDatoms' => client.seekDatoms(
        DatahikeInput(
          args['inputFormat']! as String,
          args['inputValue']! as String,
        ),
        args['indexEdn']! as String,
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'schema' => client.schema(
        DatahikeInput(
          args['inputFormat']! as String,
          args['inputValue']! as String,
        ),
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'reverseSchema' => client.reverseSchema(
        DatahikeInput(
          args['inputFormat']! as String,
          args['inputValue']! as String,
        ),
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'metrics' => client.metrics(
        DatahikeInput(
          args['inputFormat']! as String,
          args['inputValue']! as String,
        ),
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'branches' => client.branches(
        args['configEdn']! as String,
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'branch' => client.branch(
        args['configEdn']! as String,
        args['fromEdn']! as String,
        args['newBranchKeywordEdn']! as String,
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'deleteBranch' => client.deleteBranch(
        args['configEdn']! as String,
        args['branchKeywordEdn']! as String,
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'commitId' => client.commitId(
        DatahikeInput(
          args['inputFormat']! as String,
          args['inputValue']! as String,
        ),
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'parentCommitIds' => client.parentCommitIds(
        DatahikeInput(
          args['inputFormat']! as String,
          args['inputValue']! as String,
        ),
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'indexRange' => client.indexRange(
        DatahikeInput(
          args['inputFormat']! as String,
          args['inputValue']! as String,
        ),
        args['attridEdn']! as String,
        args['startEdn']! as String,
        args['endEdn']! as String,
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'gcStorage' => client.gcStorage(
        args['configEdn']! as String,
        DateTime.fromMillisecondsSinceEpoch(args['beforeTxMs']! as int),
        outputFormat: _format(args['outputFormat'] as String),
      ),
      'mergeDb' => client.mergeDb(
        args['configEdn']! as String,
        args['parentsEdn']! as String,
        args['txData']! as String,
        txFormat: _format(args['txFormat'] as String?),
        outputFormat: _format(args['outputFormat'] as String),
      ),
      _ => left(DatahikeInvalidInputFailure('Unknown isolate command: $cmd')),
    };

    result.match(
      (failure) => replyPort.send({'failure': _serializeFailure(failure)}),
      (value) => replyPort.send({'success': value}),
    );
  } on Object catch (e) {
    replyPort.send({
      'failure': _serializeFailure(
        DatahikeNativeFailure('Isolate execution error: $e', e),
      ),
    });
  }
}

Map<String, String> _serializeFailure(DatahikeFailure failure) => {
  'type': failure.runtimeType.toString(),
  'message': failure.message,
};

DatahikeFormat _format(String? name) => switch (name) {
  'json' => DatahikeFormat.json,
  'cbor' => DatahikeFormat.cbor,
  _ => DatahikeFormat.edn,
};

// ---------------------------------------------------------------------------
// Internal message types
// ---------------------------------------------------------------------------

final class _WorkerInit {
  const _WorkerInit(this.mainSendPort, {this.libraryPath});

  final SendPort mainSendPort;
  final String? libraryPath;
}

final class _WorkerCommand {
  const _WorkerCommand(this.cmd, this.args, this.replyPort);

  final String cmd;
  final Map<String, Object?> args;
  final SendPort replyPort;
}

final class _ShutdownCommand {
  const _ShutdownCommand();
}
