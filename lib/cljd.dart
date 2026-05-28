/// ClojureDart-friendly functional API for datahike4dart.
///
/// Use this entry point from ClojureDart instead of the main library:
///
/// ```clojure
/// (require '["package:datahike4dart/cljd.dart" :as dh])
///
/// (let [db (dh/open)]
///   (try
///     (let [cfg (dh/file-config "/tmp/my-db" "uuid" :write)]
///       (dh/create-db db cfg)
///       (dh/transact db cfg (dh/schema-tx
///                              [(dh/->SchemaAttribute ":name" :string :one)]))
///       (dh/transact db cfg (dh/tx-data
///                              [(dh/entity-map {":name" (dh/edn-value "Alice")})]))
///       (println (dh/q db cfg "[:find ?e :where [?e :name ?n]]")))
///     (finally (dh/close db))))
/// ```
///
/// This API throws [DatahikeException] on failures instead of returning
/// `Either` monads, which is the natural error model for ClojureDart.
library;

export 'src/cljd.dart';
