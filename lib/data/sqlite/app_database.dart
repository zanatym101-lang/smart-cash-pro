import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/claim.dart';
import '../../models/daily_close.dart';
import '../../models/recent_number.dart';
import '../../models/transaction.dart';
import '../../models/wallet.dart';

part 'app_database.g.dart';

@DataClassName('DbWallet')
class Wallets extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  BoolColumn get allowNegative =>
      boolean().withDefault(const Constant(false))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  RealColumn get dailyLimit => real()();
  RealColumn get monthlyLimit => real()();
  RealColumn get lowBalanceThreshold => real()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DbTxn')
class Txns extends Table {
  IntColumn get id => integer()();
  TextColumn get kind => text()();
  TextColumn get status => text()();
  DateTimeColumn get entryDate => dateTime()();
  IntColumn get walletFromId => integer().nullable()();
  IntColumn get walletToId => integer().nullable()();
  RealColumn get amount => real()();
  RealColumn get clientFee => real()();
  RealColumn get networkFee => real()();
  TextColumn get mode => text()();
  TextColumn get note => text().nullable()();
  TextColumn get serviceName => text().nullable()();
  TextColumn get reference => text().nullable()();
  TextColumn get party => text().nullable()();
  TextColumn get createdBy => text()();
  TextColumn get createdRole => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DbClaim')
class Claims extends Table {
  IntColumn get id => integer()();
  TextColumn get type => text()();
  TextColumn get party => text()();
  RealColumn get amount => real()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get entryDate => dateTime()();
  TextColumn get status => text()();
  IntColumn get settledTxnId => integer().nullable()();
  DateTimeColumn get settledDate => dateTime().nullable()();
  IntColumn get sourceTxnId => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DbDailyClose')
class DailyCloses extends Table {
  IntColumn get id => integer()();
  TextColumn get dateKey => text()();
  DateTimeColumn get closedAt => dateTime()();
  RealColumn get drawerBalance => real()();
  RealColumn get walletsTotal => real()();
  RealColumn get treasuryTotal => real()();
  RealColumn get profitTotal => real()();
  RealColumn get profitTransfer => real()();
  RealColumn get profitReceive => real()();
  RealColumn get profitFawry => real()();
  RealColumn get inflow => real()();
  RealColumn get outflow => real()();
  RealColumn get net => real()();
  IntColumn get transferCount => integer()();
  IntColumn get receiveCount => integer()();
  IntColumn get fawryCashCount => integer()();
  IntColumn get fawryCreditCount => integer()();
  IntColumn get expenseCount => integer()();
  IntColumn get claimCollectCount => integer()();
  IntColumn get claimPayCount => integer()();
  IntColumn get pendingCount => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DbRecentNumber')
class RecentNumbers extends Table {
  TextColumn get phone => text()();
  TextColumn get name => text().nullable()();
  DateTimeColumn get lastUsed => dateTime()();

  @override
  Set<Column> get primaryKey => {phone};
}

@DataClassName('DbMeta')
class Meta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('DbOutbox')
class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get action => text()();
  TextColumn get payload => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get sentAt => dateTime().nullable()();
}

LazyDatabase _openConnection([String? customPath]) {
  return LazyDatabase(() async {
    final file = customPath == null
        ? File(
            p.join(
              (await getApplicationSupportDirectory()).path,
              'king_wallet.db',
            ),
          )
        : File(customPath);
    return NativeDatabase(file);
  });
}

@DriftDatabase(
  tables: [Wallets, Txns, Claims, DailyCloses, RecentNumbers, Meta, SyncOutbox],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase({String? customPath}) : super(_openConnection(customPath));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(syncOutbox);
      }
    },
  );

  Future<bool> hasAnyData() async {
    final counts = await customSelect('''
      SELECT
        (SELECT COUNT(*) FROM wallets) AS wallets_count,
        (SELECT COUNT(*) FROM txns) AS txns_count,
        (SELECT COUNT(*) FROM claims) AS claims_count,
        (SELECT COUNT(*) FROM daily_closes) AS closes_count,
        (SELECT COUNT(*) FROM recent_numbers) AS recent_count,
        (SELECT COUNT(*) FROM meta) AS meta_count
      ''').getSingle();
    int read(String key) => counts.data[key] as int? ?? 0;
    return read('wallets_count') > 0 ||
        read('txns_count') > 0 ||
        read('claims_count') > 0 ||
        read('closes_count') > 0 ||
        read('recent_count') > 0 ||
        read('meta_count') > 0;
  }

  Future<void> clearAll() async {
    await transaction(() async {
      await delete(wallets).go();
      await delete(txns).go();
      await delete(claims).go();
      await delete(dailyCloses).go();
      await delete(recentNumbers).go();
      await delete(meta).go();
      await delete(syncOutbox).go();
    });
  }

  Future<List<Wallet>> loadWallets() async {
    final rows = await select(wallets).get();
    return rows
        .map(
          (r) => Wallet(
            id: r.id,
            name: r.name,
            allowNegative: r.allowNegative,
            phone: r.phone,
            dailyLimit: r.dailyLimit,
            monthlyLimit: r.monthlyLimit,
            lowBalanceThreshold: r.lowBalanceThreshold,
          ),
        )
        .toList();
  }

  Future<void> saveWallets(List<Wallet> items) async {
    await batch((b) {
      b.deleteAll(wallets);
      b.insertAll(
        wallets,
        items.map(
          (w) => WalletsCompanion.insert(
            id: Value(w.id),
            name: w.name,
            allowNegative: Value(w.allowNegative),
            phone: Value(w.phone),
            dailyLimit: w.dailyLimit,
            monthlyLimit: w.monthlyLimit,
            lowBalanceThreshold: w.lowBalanceThreshold,
          ),
        ),
      );
    });
  }

  Future<List<Txn>> loadTxns() async {
    final rows = await select(txns).get();
    return rows
        .map(
          (r) => Txn(
            id: r.id,
            kind: r.kind,
            status: r.status,
            entryDate: r.entryDate,
            walletFromId: r.walletFromId,
            walletToId: r.walletToId,
            amount: r.amount,
            clientFee: r.clientFee,
            networkFee: r.networkFee,
            mode: r.mode,
            note: r.note,
            serviceName: r.serviceName,
            reference: r.reference,
            party: r.party,
            createdBy: r.createdBy,
            createdRole: r.createdRole,
            createdAt: r.createdAt,
          ),
        )
        .toList();
  }

  Future<void> saveTxns(List<Txn> items) async {
    await batch((b) {
      b.deleteAll(txns);
      b.insertAll(
        txns,
        items.map(
          (t) => TxnsCompanion.insert(
            id: Value(t.id),
            kind: t.kind,
            status: t.status,
            entryDate: t.entryDate,
            walletFromId: Value(t.walletFromId),
            walletToId: Value(t.walletToId),
            amount: t.amount,
            clientFee: t.clientFee,
            networkFee: t.networkFee,
            mode: t.mode,
            note: Value(t.note),
            serviceName: Value(t.serviceName),
            reference: Value(t.reference),
            party: Value(t.party),
            createdBy: t.createdBy,
            createdRole: t.createdRole,
            createdAt: t.createdAt,
          ),
        ),
      );
    });
  }

  Future<List<Claim>> loadClaims() async {
    final rows = await select(claims).get();
    return rows
        .map(
          (r) => Claim(
            id: r.id,
            type: r.type,
            party: r.party,
            amount: r.amount,
            note: r.note,
            entryDate: r.entryDate,
            status: r.status,
            settledTxnId: r.settledTxnId,
            settledDate: r.settledDate,
            sourceTxnId: r.sourceTxnId,
          ),
        )
        .toList();
  }

  Future<void> saveClaims(List<Claim> items) async {
    await batch((b) {
      b.deleteAll(claims);
      b.insertAll(
        claims,
        items.map(
          (c) => ClaimsCompanion.insert(
            id: Value(c.id),
            type: c.type,
            party: c.party,
            amount: c.amount,
            note: Value(c.note),
            entryDate: c.entryDate,
            status: c.status,
            settledTxnId: Value(c.settledTxnId),
            settledDate: Value(c.settledDate),
            sourceTxnId: Value(c.sourceTxnId),
          ),
        ),
      );
    });
  }

  Future<List<DailyClose>> loadDailyCloses() async {
    final rows = await select(dailyCloses).get();
    return rows
        .map(
          (r) => DailyClose(
            id: r.id,
            dateKey: r.dateKey,
            closedAt: r.closedAt,
            drawerBalance: r.drawerBalance,
            walletsTotal: r.walletsTotal,
            treasuryTotal: r.treasuryTotal,
            profitTotal: r.profitTotal,
            profitTransfer: r.profitTransfer,
            profitReceive: r.profitReceive,
            profitFawry: r.profitFawry,
            inflow: r.inflow,
            outflow: r.outflow,
            net: r.net,
            transferCount: r.transferCount,
            receiveCount: r.receiveCount,
            fawryCashCount: r.fawryCashCount,
            fawryCreditCount: r.fawryCreditCount,
            expenseCount: r.expenseCount,
            claimCollectCount: r.claimCollectCount,
            claimPayCount: r.claimPayCount,
            pendingCount: r.pendingCount,
          ),
        )
        .toList();
  }

  Future<void> saveDailyCloses(List<DailyClose> items) async {
    await batch((b) {
      b.deleteAll(dailyCloses);
      b.insertAll(
        dailyCloses,
        items.map(
          (c) => DailyClosesCompanion.insert(
            id: Value(c.id),
            dateKey: c.dateKey,
            closedAt: c.closedAt,
            drawerBalance: c.drawerBalance,
            walletsTotal: c.walletsTotal,
            treasuryTotal: c.treasuryTotal,
            profitTotal: c.profitTotal,
            profitTransfer: c.profitTransfer,
            profitReceive: c.profitReceive,
            profitFawry: c.profitFawry,
            inflow: c.inflow,
            outflow: c.outflow,
            net: c.net,
            transferCount: c.transferCount,
            receiveCount: c.receiveCount,
            fawryCashCount: c.fawryCashCount,
            fawryCreditCount: c.fawryCreditCount,
            expenseCount: c.expenseCount,
            claimCollectCount: c.claimCollectCount,
            claimPayCount: c.claimPayCount,
            pendingCount: c.pendingCount,
          ),
        ),
      );
    });
  }

  Future<List<RecentNumber>> loadRecentNumbers() async {
    final rows = await select(recentNumbers).get();
    return rows
        .map(
          (r) =>
              RecentNumber(phone: r.phone, name: r.name, lastUsed: r.lastUsed),
        )
        .toList();
  }

  Future<void> saveRecentNumbers(List<RecentNumber> items) async {
    await batch((b) {
      b.deleteAll(recentNumbers);
      b.insertAll(
        recentNumbers,
        items.map(
          (r) => RecentNumbersCompanion.insert(
            phone: r.phone,
            name: Value(r.name),
            lastUsed: r.lastUsed,
          ),
        ),
      );
    });
  }

  Future<Map<String, String>> loadMeta() async {
    final rows = await select(meta).get();
    return {for (final r in rows) r.key: r.value};
  }

  Future<void> saveMeta(Map<String, String> items) async {
    await batch((b) {
      b.deleteAll(meta);
      b.insertAll(
        meta,
        items.entries.map(
          (e) => MetaCompanion.insert(key: e.key, value: e.value),
        ),
      );
    });
  }

  Future<void> saveSnapshot({
    required List<Wallet> walletItems,
    required List<Txn> txnItems,
    required List<Claim> claimItems,
    required List<DailyClose> dailyCloseItems,
    required List<RecentNumber> recentNumberItems,
    required Map<String, String> metaItems,
  }) async {
    await transaction(() async {
      await batch((b) {
        b.deleteAll(wallets);
        b.deleteAll(txns);
        b.deleteAll(claims);
        b.deleteAll(dailyCloses);
        b.deleteAll(recentNumbers);
        b.deleteAll(meta);

        if (walletItems.isNotEmpty) {
          b.insertAll(
            wallets,
            walletItems.map(
              (w) => WalletsCompanion.insert(
                id: Value(w.id),
                name: w.name,
                allowNegative: Value(w.allowNegative),
                phone: Value(w.phone),
                dailyLimit: w.dailyLimit,
                monthlyLimit: w.monthlyLimit,
                lowBalanceThreshold: w.lowBalanceThreshold,
              ),
            ),
          );
        }

        if (txnItems.isNotEmpty) {
          b.insertAll(
            txns,
            txnItems.map(
              (t) => TxnsCompanion.insert(
                id: Value(t.id),
                kind: t.kind,
                status: t.status,
                entryDate: t.entryDate,
                walletFromId: Value(t.walletFromId),
                walletToId: Value(t.walletToId),
                amount: t.amount,
                clientFee: t.clientFee,
                networkFee: t.networkFee,
                mode: t.mode,
                note: Value(t.note),
                serviceName: Value(t.serviceName),
                reference: Value(t.reference),
                party: Value(t.party),
                createdBy: t.createdBy,
                createdRole: t.createdRole,
                createdAt: t.createdAt,
              ),
            ),
          );
        }

        if (claimItems.isNotEmpty) {
          b.insertAll(
            claims,
            claimItems.map(
              (c) => ClaimsCompanion.insert(
                id: Value(c.id),
                type: c.type,
                party: c.party,
                amount: c.amount,
                note: Value(c.note),
                entryDate: c.entryDate,
                status: c.status,
                settledTxnId: Value(c.settledTxnId),
                settledDate: Value(c.settledDate),
                sourceTxnId: Value(c.sourceTxnId),
              ),
            ),
          );
        }

        if (dailyCloseItems.isNotEmpty) {
          b.insertAll(
            dailyCloses,
            dailyCloseItems.map(
              (c) => DailyClosesCompanion.insert(
                id: Value(c.id),
                dateKey: c.dateKey,
                closedAt: c.closedAt,
                drawerBalance: c.drawerBalance,
                walletsTotal: c.walletsTotal,
                treasuryTotal: c.treasuryTotal,
                profitTotal: c.profitTotal,
                profitTransfer: c.profitTransfer,
                profitReceive: c.profitReceive,
                profitFawry: c.profitFawry,
                inflow: c.inflow,
                outflow: c.outflow,
                net: c.net,
                transferCount: c.transferCount,
                receiveCount: c.receiveCount,
                fawryCashCount: c.fawryCashCount,
                fawryCreditCount: c.fawryCreditCount,
                expenseCount: c.expenseCount,
                claimCollectCount: c.claimCollectCount,
                claimPayCount: c.claimPayCount,
                pendingCount: c.pendingCount,
              ),
            ),
          );
        }

        if (recentNumberItems.isNotEmpty) {
          b.insertAll(
            recentNumbers,
            recentNumberItems.map(
              (r) => RecentNumbersCompanion.insert(
                phone: r.phone,
                name: Value(r.name),
                lastUsed: r.lastUsed,
              ),
            ),
          );
        }

        if (metaItems.isNotEmpty) {
          b.insertAll(
            meta,
            metaItems.entries.map(
              (e) => MetaCompanion.insert(key: e.key, value: e.value),
            ),
          );
        }
      });
    });
  }

  Future<int> addOutbox({
    required String entity,
    required String entityId,
    required String action,
    String? payload,
  }) async {
    return into(syncOutbox).insert(
      SyncOutboxCompanion.insert(
        entity: entity,
        entityId: entityId,
        action: action,
        payload: Value(payload),
        createdAt: DateTime.now(),
        sentAt: const Value.absent(),
      ),
    );
  }

  Future<List<DbOutbox>> pendingOutbox({int limit = 100}) async {
    final q = (select(syncOutbox)
      ..where((t) => t.sentAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc),
      ])
      ..limit(limit));
    return q.get();
  }

  Future<void> markOutboxSent(int id) async {
    await (update(syncOutbox)..where((t) => t.id.equals(id))).write(
      SyncOutboxCompanion(sentAt: Value(DateTime.now())),
    );
  }

  Future<void> clearOutbox() async {
    await delete(syncOutbox).go();
  }
}
