import 'dart:io';

import 'package:datahike4dart/datahike4dart.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const DatahikeExampleApp());
}

class DatahikeExampleApp extends StatelessWidget {
  const DatahikeExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'datahike4dart example',
      theme: ThemeData(colorSchemeSeed: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DatahikeIsolate? _service;
  String _status = 'Tap Start to open Datahike.';
  List<String> _rows = [];

  Future<void> _start() async {
    setState(() => _status = 'Starting worker isolate...');
    try {
      _service = await DatahikeIsolate.start();
      setState(() => _status = 'Worker isolate ready.');
    } on Object catch (e) {
      setState(() => _status = 'Failed to start: $e');
    }
  }

  Future<void> _setupDb() async {
    if (_service == null) {
      setState(() => _status = 'Start the worker first.');
      return;
    }
    setState(() => _status = 'Creating database...');

    final dbDir = Directory.systemTemp.createTempSync('datahike_flutter_');
    final config = DatahikeConfig.file(
      path: '${dbDir.path}/db',
      id: 'f11e0000-0000-0000-0000-000000000001',
      schemaFlexibility: SchemaFlexibility.write,
    ).toEdn();

    final create = await _service!.createDatabase(config);
    if (create.isLeft()) {
      setState(
        () => _status = 'Create failed: ${create.swap().getOrElse((_) => '')}',
      );
      return;
    }

    final schema = await _service!.transact(
      config,
      schemaTx([
        const SchemaAttribute(
          ident: ':person/name',
          valueType: ValueType.string,
          cardinality: Cardinality.one,
        ),
        const SchemaAttribute(
          ident: ':person/age',
          valueType: ValueType.long,
          cardinality: Cardinality.one,
        ),
      ]),
    );
    if (schema.isLeft()) {
      setState(
        () => _status = 'Schema failed: ${schema.swap().getOrElse((_) => '')}',
      );
      return;
    }

    final data = await _service!.transact(
      config,
      txData([
        entityMap({
          ':person/name': ednValue('Alice'),
          ':person/age': ednValue(30),
        }),
        entityMap({
          ':person/name': ednValue('Bob'),
          ':person/age': ednValue(25),
        }),
      ]),
    );
    if (data.isLeft()) {
      setState(
        () => _status = 'Data failed: ${data.swap().getOrElse((_) => '')}',
      );
      return;
    }

    setState(() => _status = 'Database created and seeded.\nConfig:\n$config');
  }

  Future<void> _query() async {
    if (_service == null) {
      setState(() => _status = 'Start the worker first.');
      return;
    }
    setState(() => _status = 'Querying...');

    final config = DatahikeConfig.file(
      path: '/tmp/datahike_flutter_example/db',
      id: 'f11e0000-0000-0000-0000-000000000001',
      schemaFlexibility: SchemaFlexibility.write,
    ).toEdn();

    final result = await _service!.qRows(
      '[:find ?name ?age :where [_ :person/name ?name] [_ :person/age ?age]]',
      [DatahikeInput.database(config)],
    );

    result.match(
      (failure) => setState(() => _status = 'Query failed: $failure'),
      (rows) => setState(() {
        _rows = rows.map((r) => '${r[0]} (age ${r[1]})').toList();
        _status = 'Found ${_rows.length} rows';
      }),
    );
  }

  Future<void> _stop() async {
    setState(() => _status = 'Stopping...');
    await _service?.close();
    _service = null;
    setState(() {
      _status = 'Worker stopped.';
      _rows = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('datahike4dart example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _service == null ? _start : null,
                  child: const Text('Start'),
                ),
                ElevatedButton(
                  onPressed: _service != null ? _setupDb : null,
                  child: const Text('Setup DB'),
                ),
                ElevatedButton(
                  onPressed: _service != null ? _query : null,
                  child: const Text('Query'),
                ),
                ElevatedButton(
                  onPressed: _service != null ? _stop : null,
                  child: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(_status, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _rows.length,
                itemBuilder: (context, index) =>
                    ListTile(title: Text(_rows[index])),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
