# Changelog

## [0.1.0] - 2026-05-28

### Added

- Dart FFI bindings for libdatahike via dart:ffi
- Database lifecycle: createDatabase, deleteDatabase, databaseExists
- Data operations: transact, mergeDb
- Query API: q, pull, pullMany, entity
- Index and metadata access: datoms, seekDatoms, indexRange, schema, reverseSchema, metrics
- Versioning and branching: commitId, parentCommitIds, branch, branches, deleteBranch
- Storage management: gcStorage
- Functional API (DatahikeClient) with fpdart Either error handling
- Raw FFI API (Datahike) for advanced use cases
- EDN, JSON, and CBOR serialization format support
- Multiple database input modes: database, history, as-of, since, branch, commit
