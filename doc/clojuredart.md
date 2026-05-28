# ClojureDart interop guide

`datahike4dart` is a Dart package. ClojureDart compiles to Dart, so you can consume it directly via Dart interop.

This guide shows the idiomatic way to use the library from ClojureDart.

## Dependency

Add to `deps.edn`:

```clojure
{:deps {tensegritics/datahike4dart {:local/root "path/to/datahike4dart"}}}
```

Or via Git:

```clojure
{:deps {tensegritics/datahike4dart
        {:git/url "https://github.com/yourname/datahike4dart"
         :sha "..."}}}
```

Then in your ClojureDart namespace:

```clojure
(ns my-app.core
  (:require ["package:datahike4dart/cljd.dart" :as dh]))
```

## Design philosophy

The main `datahike4dart` API is very Dart-idiomatic:

- Classes with named constructors (`DatahikeConfig.file(...)`)
- `Either<DatahikeFailure, T>` return types for error handling
- Method chains on `DatahikeClient`

The `cljd.dart` entry point provides a thin functional wrapper:

- Top-level functions instead of class methods
- Exceptions instead of `Either`
- Positional arguments with simple defaults
- Direct EDN strings for config, queries, and transactions

## Quick start

```clojure
(ns my-app.core
  (:require ["package:datahike4dart/cljd.dart" :as dh]))

(defn -main []
  (let [db (dh/open)]
    (try
      (let [cfg (dh/file-config "/tmp/my-db"
                                "f11e0000-0000-0000-0000-000000000001"
                                :write)]
        (dh/create-db db cfg)

        ;; Schema
        (dh/transact db cfg
                     (dh/schema-tx
                       [(dh/->SchemaAttribute ":name" :string :one)]))

        ;; Data
        (dh/transact db cfg
                     (dh/tx-data
                       [(dh/entity-map {":name" (dh/edn-value "Alice")})]))

        ;; Query
        (println (dh/q db cfg "[:find ?e ?name :where [?e :name ?name]]")))

      (finally
        (dh/close db)))))
```

## API reference

### Lifecycle

| Function | Description |
|----------|-------------|
| `(dh/open)` | Returns a `DatahikeClient`. Throws on native library load failure. |
| `(dh/open :libraryPath "/path/to/libdatahike.dylib")` | Explicit library path. |
| `(dh/close db)` | Releases native resources. |

### Config

| Function | Description |
|----------|-------------|
| `(dh/file-config path id & opts)` | Returns EDN config string for file store. |
| `(dh/memory-config id & opts)` | Returns EDN config string for memory store. |

Options (all optional):
- `:schemaFlexibility` — `:write` (default) or `:read`
- `:keepHistory` — `true` or `false` (default)
- `:initialTx` — EDN string for initial transaction

Example:

```clojure
(dh/file-config "/tmp/db" "my-uuid" :schemaFlexibility :read :keepHistory true)
```

### Database operations

| Function | Description |
|----------|-------------|
| `(dh/create-db db cfg)` | Creates the database. |
| `(dh/delete-db db cfg)` | Deletes the database. |
| `(dh/db-exists db cfg)` | Returns `true`/`false`. |
| `(dh/transact db cfg tx-data)` | Runs a transaction. Returns EDN result. |

### Query / read

| Function | Description |
|----------|-------------|
| `(dh/q db cfg query)` | Returns raw EDN query result. |
| `(dh/q-rows db cfg query)` | Returns `List<List<Object?>>`. |
| `(dh/pull db cfg selector eid)` | Returns raw EDN pull result. |
| `(dh/entity db cfg eid)` | Returns `Map<Object?, Object?>?`. |
| `(dh/schema db cfg)` | Returns raw EDN schema. |
| `(dh/datoms db cfg ":eavt")` | Returns `List<List<Object?>>`. |

### Transaction helpers

| Function | Description |
|----------|-------------|
| `(dh/->SchemaAttribute ident valueType cardinality & opts)` | Schema attribute builder. |
| `(dh/db-add eid attr value)` | Returns `[:db/add ...]` EDN. |
| `(dh/db-retract eid attr value)` | Returns `[:db/retract ...]` EDN. |
| `(dh/edn-value value)` | Converts Dart/Clojure value to EDN string. |
| `(dh/tx-data operations)` | Wraps a list of EDN ops in a transaction vector. |
| `(dh/schema-tx attributes)` | Builds a schema transaction from attributes. |
| `(dh/entity-map attrs)` | Builds a map-form entity insert. |

## Working with enums

Enums are Dart interop values. Reference them directly:

```clojure
dh/ValueType/string
dh/ValueType/long
dh/Cardinality/one
dh/Cardinality/many
dh/Uniqueness/identity
```

## Error handling

All functions throw `DatahikeException` on failure. Use `try`/`catch`:

```clojure
(try
  (dh/q db cfg "[:find ?e :where [?e :name ?n]]")
  (catch DatahikeException e
    (println "Datahike error:" e)))
```

## Async / Flutter

For Flutter apps, use `DatahikeIsolate` from the main Dart API (not yet wrapped for ClojureDart):

```clojure
(require '["package:datahike4dart/datahike4dart.dart" :as dh-raw])

(let [service (await (.-start dh-raw/DatahikeIsolate))]
  (try
    (let [result (await (.q service "[:find ?e ...]" [...]))]
      ...)
    (finally
      (await (.close service)))))
```

For CLI or server-side ClojureDart, the synchronous `dh/open` API is fine.

## Why a separate `cljd.dart` entry point?

The main `datahike4dart.dart` export is optimized for Dart developers:

- `DatahikeClient.open()` returns `Either<DatahikeFailure, DatahikeClient>`
- Named parameters everywhere
- Rich typed result helpers (`qRows`, `pullMap`, `entityMap`)

The `cljd.dart` entry point wraps all of this with:

- Exception-based error handling (idiomatic for Clojure)
- Top-level functions (no OOP boilerplate)
- Simplified positional arguments

If you are writing Dart, use `package:datahike4dart/datahike4dart.dart`.
If you are writing ClojureDart, use `package:datahike4dart/cljd.dart`.
