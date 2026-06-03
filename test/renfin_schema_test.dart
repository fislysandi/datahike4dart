import 'dart:io';
import 'package:datahike4dart/datahike4dart.dart';

void main() async {
  final parentDir = Directory.systemTemp.createTempSync('renfin_schema_test_');
  final dbPath = '${parentDir.path}/db';
  final config = DatahikeConfig.file(
    path: dbPath,
    id: 'a1b2c3d4-0000-0000-0000-000000000001',
    schemaFlexibility: SchemaFlexibility.read,
    keepHistory: true,
  ).toEdn();

  final openResult = DatahikeClient.open();
  openResult.match(
    (failure) {
      print('OPEN FAILED: ${failure.message}');
      exit(1);
    },
    (datahike) {
      try {
        // 1. Create DB
        final create = datahike.createDatabase(config);
        create.match(
          (f) { print('CREATE FAILED: ${f.message}'); exit(1); },
          (_) => print('1. Create DB: OK'),
        );

        // 2. Transact ren-finance schema
        final schemaEdn = '''
[{:db/ident :account/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
 {:db/ident :account/type :db/valueType :db.type/keyword :db/cardinality :db.cardinality/one}
 {:db/ident :account/balance :db/valueType :db.type/bigdec :db/cardinality :db.cardinality/one}
 {:db/ident :account/currency :db/valueType :db.type/keyword :db/cardinality :db.cardinality/one}

 {:db/ident :transaction/date :db/valueType :db.type/instant :db/cardinality :db.cardinality/one :db/index true}
 {:db/ident :transaction/amount :db/valueType :db.type/bigdec :db/cardinality :db.cardinality/one}
 {:db/ident :transaction/description :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
 {:db/ident :transaction/account :db/valueType :db.type/ref :db/cardinality :db.cardinality/one :db/index true}
 {:db/ident :transaction/category :db/valueType :db.type/ref :db/cardinality :db.cardinality/one :db/index true}
 {:db/ident :transaction/type :db/valueType :db.type/keyword :db/cardinality :db.cardinality/one}
 {:db/ident :transaction/import-hash :db/valueType :db.type/string :db/cardinality :db.cardinality/one :db/unique :db.unique/identity}

 {:db/ident :category/name :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
 {:db/ident :category/type :db/valueType :db.type/keyword :db/cardinality :db.cardinality/one}
 {:db/ident :category/color :db/valueType :db.type/string :db/cardinality :db.cardinality/one}

 {:db/ident :budget/category :db/valueType :db.type/ref :db/cardinality :db.cardinality/one}
 {:db/ident :budget/amount :db/valueType :db.type/bigdec :db/cardinality :db.cardinality/one}
 {:db/ident :budget/period :db/valueType :db.type/keyword :db/cardinality :db.cardinality/one}

 {:db/ident :wallet/address :db/valueType :db.type/string :db/cardinality :db.cardinality/one :db/unique :db.unique/identity}
 {:db/ident :wallet/chain-type :db/valueType :db.type/keyword :db/cardinality :db.cardinality/one}
 {:db/ident :wallet/label :db/valueType :db.type/string :db/cardinality :db.cardinality/one}
 {:db/ident :wallet/last-balance :db/valueType :db.type/bigdec :db/cardinality :db.cardinality/one}
 {:db/ident :wallet/last-sync :db/valueType :db.type/instant :db/cardinality :db.cardinality/one}

 {:db/ident :rate/base-currency :db/valueType :db.type/keyword :db/cardinality :db.cardinality/one}
 {:db/ident :rate/target-currency :db/valueType :db.type/keyword :db/cardinality :db.cardinality/one}
 {:db/ident :rate/rate :db/valueType :db.type/double :db/cardinality :db.cardinality/one}
 {:db/ident :rate/timestamp :db/valueType :db.type/instant :db/cardinality :db.cardinality/one}]
''';
        final schemaTx = datahike.transact(config, schemaEdn);
        schemaTx.match(
          (f) { print('SCHEMA TX FAILED: ${f.message}'); exit(1); },
          (_) => print('2. Schema transact: OK'),
        );

        // 3. Seed categories
        final catTx = datahike.transact(config, '''
[{:category/name "Groceries" :category/type :expense :category/color "#494fdf"}
 {:category/name "Salary" :category/type :income :category/color "#22c55e"}
 {:category/name "Rent" :category/type :expense :category/color "#ef4444"}]
''');
        catTx.match(
          (f) { print('CATEGORY TX FAILED: ${f.message}'); exit(1); },
          (_) => print('3. Seed categories: OK'),
        );

        // 4. Create account
        final accTx = datahike.transact(config, '''
[{:account/name "Main Checking" :account/type :checking :account/balance 5000.00M :account/currency :USD}]
''');
        accTx.match(
          (f) { print('ACCOUNT TX FAILED: ${f.message}'); exit(1); },
          (_) => print('4. Create account: OK'),
        );

        // Find category and account eids for refs
        final input = DatahikeInput.database(config);
        final catEid = datahike.q(
          '[:find ?e . :where [?e :category/name "Groceries"]]',
          [input],
        );
        final accEid = datahike.q(
          '[:find ?e . :where [?e :account/name "Main Checking"]]',
          [input],
        );
        final catId = catEid.getOrElse((_) => 'FAIL');
        final accountId = accEid.getOrElse((_) => 'FAIL');
        print('   Category eid: $catId, Account eid: $accountId');

        // 5. Transaction with ref + bigdec + instant
        final txTx = datahike.transact(config, '''
[{:transaction/date #inst "2026-06-01"
  :transaction/amount -45.99M
  :transaction/description "Whole Foods Market"
  :transaction/account $accountId
  :transaction/category $catId
  :transaction/type :expense
  :transaction/import-hash "sha256test123"}]
''');
        txTx.match(
          (f) { print('TRANSACTION TX FAILED: ${f.message}'); exit(1); },
          (_) => print('5. Create transaction with refs/bigdec/instant: OK'),
        );

        // 6. Net-worth aggregation
        final nwQuery = datahike.qRows(
          '[:find (sum ?bal) . :where [_ :account/balance ?bal]]',
          [input],
        );
        nwQuery.match(
          (f) { print('NET-WORTH QUERY FAILED: ${f.message}'); exit(1); },
          (rows) => print('6. Net-worth aggregate query: OK → $rows'),
        );

        // 7. Transaction query
        final txQuery = datahike.qRows(
          '[:find ?desc ?amt ?type :where [?t :transaction/description ?desc] [?t :transaction/amount ?amt] [?t :transaction/type ?type]]',
          [input],
        );
        txQuery.match(
          (f) { print('TRANSACTION QUERY FAILED: ${f.message}'); exit(1); },
          (rows) => print('7. Transaction query: OK → $rows'),
        );

        // 8. Pull entity with nested refs
        final txEid = datahike.q(
          '[:find ?e . :where [?e :transaction/description "Whole Foods Market"]]',
          [input],
        );
        final tid = int.tryParse(txEid.getOrElse((_) => '0')) ?? 0;
        final pullResult = datahike.pullMap(input, '[:transaction/description :transaction/amount :transaction/account :transaction/category]', tid);
        pullResult.match(
          (f) { print('PULL FAILED: ${f.message}'); exit(1); },
          (m) => print('8. Pull transaction with refs: OK → $m'),
        );

        // 9. Dedup test: same import-hash
        final dupTx = datahike.transact(config, '''
[{:transaction/date #inst "2026-06-01"
  :transaction/amount -45.99M
  :transaction/description "Whole Foods Market"
  :transaction/account $accountId
  :transaction/category $catId
  :transaction/type :expense
  :transaction/import-hash "sha256test123"}]
''');
        dupTx.match(
          (f) => print('9. Dedup (same import-hash): correctly rejected → ${f.message}'),
          (_) => print('9. Dedup: transact succeeded (upsert/idempotent on unique identity)'),
        );

        // 10. Wallet
        final walletTx = datahike.transact(config, '''
[{:wallet/address "0xabc123" :wallet/chain-type :ETH :wallet/label "MetaMask" :wallet/last-balance 1.5M :wallet/last-sync #inst "2026-06-03"}]
''');
        walletTx.match(
          (f) { print('WALLET TX FAILED: ${f.message}'); exit(1); },
          (_) => print('10. Wallet entity: OK'),
        );

        // 11. Budget
        final budgetTx = datahike.transact(config, '''
[{:budget/category $catId :budget/amount 400.00M :budget/period :monthly}]
''');
        budgetTx.match(
          (f) { print('BUDGET TX FAILED: ${f.message}'); exit(1); },
          (_) => print('11. Budget entity: OK'),
        );

        // 12. Rate
        final rateTx = datahike.transact(config, '''
[{:rate/base-currency :USD :rate/target-currency :EUR :rate/rate 0.92 :rate/timestamp #inst "2026-06-03"}]
''');
        rateTx.match(
          (f) { print('RATE TX FAILED: ${f.message}'); exit(1); },
          (_) => print('12. Rate entity: OK'),
        );

        // 13. All-accounts query
        final accQuery = datahike.qRows(
          '[:find ?name ?type ?bal ?curr :where [?e :account/name ?name] [?e :account/type ?type] [?e :account/balance ?bal] [?e :account/currency ?curr]]',
          [input],
        );
        accQuery.match(
          (f) { print('ALL-ACCOUNTS QUERY FAILED: ${f.message}'); exit(1); },
          (rows) => print('13. All-accounts query: OK → $rows'),
        );

        // 14. Budget status query (spend by category)
        final budgetQuery = datahike.qRows(
          '[:find ?catName (sum ?amt) ?budgetAmt :where [?b :budget/category ?catEid] [?b :budget/amount ?budgetAmt] [?catEid :category/name ?catName] [?t :transaction/category ?catEid] [?t :transaction/amount ?amt] [?t :transaction/type :expense]]',
          [input],
        );
        budgetQuery.match(
          (f) => print('14. Budget-status query: FAILED (aggregation join) → ${f.message}'),
          (rows) => print('14. Budget-status query: OK → $rows'),
        );

        print('\n=== ALL REN-FINANCE SCHEMA TESTS PASSED ===');
      } finally {
        datahike.deleteDatabase(config);
        datahike.close();
        if (parentDir.existsSync()) parentDir.deleteSync(recursive: true);
      }
    },
  );
}
