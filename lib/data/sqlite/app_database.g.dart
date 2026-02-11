// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $WalletsTable extends Wallets with TableInfo<$WalletsTable, DbWallet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WalletsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _allowNegativeMeta = const VerificationMeta(
    'allowNegative',
  );
  @override
  late final GeneratedColumn<bool> allowNegative = GeneratedColumn<bool>(
    'allow_negative',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("allow_negative" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _dailyLimitMeta = const VerificationMeta(
    'dailyLimit',
  );
  @override
  late final GeneratedColumn<double> dailyLimit = GeneratedColumn<double>(
    'daily_limit',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _monthlyLimitMeta = const VerificationMeta(
    'monthlyLimit',
  );
  @override
  late final GeneratedColumn<double> monthlyLimit = GeneratedColumn<double>(
    'monthly_limit',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lowBalanceThresholdMeta =
      const VerificationMeta('lowBalanceThreshold');
  @override
  late final GeneratedColumn<double> lowBalanceThreshold =
      GeneratedColumn<double>(
        'low_balance_threshold',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    allowNegative,
    phone,
    dailyLimit,
    monthlyLimit,
    lowBalanceThreshold,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wallets';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbWallet> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('allow_negative')) {
      context.handle(
        _allowNegativeMeta,
        allowNegative.isAcceptableOrUnknown(
          data['allow_negative']!,
          _allowNegativeMeta,
        ),
      );
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('daily_limit')) {
      context.handle(
        _dailyLimitMeta,
        dailyLimit.isAcceptableOrUnknown(data['daily_limit']!, _dailyLimitMeta),
      );
    } else if (isInserting) {
      context.missing(_dailyLimitMeta);
    }
    if (data.containsKey('monthly_limit')) {
      context.handle(
        _monthlyLimitMeta,
        monthlyLimit.isAcceptableOrUnknown(
          data['monthly_limit']!,
          _monthlyLimitMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_monthlyLimitMeta);
    }
    if (data.containsKey('low_balance_threshold')) {
      context.handle(
        _lowBalanceThresholdMeta,
        lowBalanceThreshold.isAcceptableOrUnknown(
          data['low_balance_threshold']!,
          _lowBalanceThresholdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lowBalanceThresholdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DbWallet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbWallet(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      allowNegative: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}allow_negative'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      )!,
      dailyLimit: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}daily_limit'],
      )!,
      monthlyLimit: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}monthly_limit'],
      )!,
      lowBalanceThreshold: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}low_balance_threshold'],
      )!,
    );
  }

  @override
  $WalletsTable createAlias(String alias) {
    return $WalletsTable(attachedDatabase, alias);
  }
}

class DbWallet extends DataClass implements Insertable<DbWallet> {
  final int id;
  final String name;
  final bool allowNegative;
  final String phone;
  final double dailyLimit;
  final double monthlyLimit;
  final double lowBalanceThreshold;
  const DbWallet({
    required this.id,
    required this.name,
    required this.allowNegative,
    required this.phone,
    required this.dailyLimit,
    required this.monthlyLimit,
    required this.lowBalanceThreshold,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['allow_negative'] = Variable<bool>(allowNegative);
    map['phone'] = Variable<String>(phone);
    map['daily_limit'] = Variable<double>(dailyLimit);
    map['monthly_limit'] = Variable<double>(monthlyLimit);
    map['low_balance_threshold'] = Variable<double>(lowBalanceThreshold);
    return map;
  }

  WalletsCompanion toCompanion(bool nullToAbsent) {
    return WalletsCompanion(
      id: Value(id),
      name: Value(name),
      allowNegative: Value(allowNegative),
      phone: Value(phone),
      dailyLimit: Value(dailyLimit),
      monthlyLimit: Value(monthlyLimit),
      lowBalanceThreshold: Value(lowBalanceThreshold),
    );
  }

  factory DbWallet.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbWallet(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      allowNegative: serializer.fromJson<bool>(json['allowNegative']),
      phone: serializer.fromJson<String>(json['phone']),
      dailyLimit: serializer.fromJson<double>(json['dailyLimit']),
      monthlyLimit: serializer.fromJson<double>(json['monthlyLimit']),
      lowBalanceThreshold: serializer.fromJson<double>(
        json['lowBalanceThreshold'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'allowNegative': serializer.toJson<bool>(allowNegative),
      'phone': serializer.toJson<String>(phone),
      'dailyLimit': serializer.toJson<double>(dailyLimit),
      'monthlyLimit': serializer.toJson<double>(monthlyLimit),
      'lowBalanceThreshold': serializer.toJson<double>(lowBalanceThreshold),
    };
  }

  DbWallet copyWith({
    int? id,
    String? name,
    bool? allowNegative,
    String? phone,
    double? dailyLimit,
    double? monthlyLimit,
    double? lowBalanceThreshold,
  }) => DbWallet(
    id: id ?? this.id,
    name: name ?? this.name,
    allowNegative: allowNegative ?? this.allowNegative,
    phone: phone ?? this.phone,
    dailyLimit: dailyLimit ?? this.dailyLimit,
    monthlyLimit: monthlyLimit ?? this.monthlyLimit,
    lowBalanceThreshold: lowBalanceThreshold ?? this.lowBalanceThreshold,
  );
  DbWallet copyWithCompanion(WalletsCompanion data) {
    return DbWallet(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      allowNegative: data.allowNegative.present
          ? data.allowNegative.value
          : this.allowNegative,
      phone: data.phone.present ? data.phone.value : this.phone,
      dailyLimit: data.dailyLimit.present
          ? data.dailyLimit.value
          : this.dailyLimit,
      monthlyLimit: data.monthlyLimit.present
          ? data.monthlyLimit.value
          : this.monthlyLimit,
      lowBalanceThreshold: data.lowBalanceThreshold.present
          ? data.lowBalanceThreshold.value
          : this.lowBalanceThreshold,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbWallet(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('allowNegative: $allowNegative, ')
          ..write('phone: $phone, ')
          ..write('dailyLimit: $dailyLimit, ')
          ..write('monthlyLimit: $monthlyLimit, ')
          ..write('lowBalanceThreshold: $lowBalanceThreshold')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    allowNegative,
    phone,
    dailyLimit,
    monthlyLimit,
    lowBalanceThreshold,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbWallet &&
          other.id == this.id &&
          other.name == this.name &&
          other.allowNegative == this.allowNegative &&
          other.phone == this.phone &&
          other.dailyLimit == this.dailyLimit &&
          other.monthlyLimit == this.monthlyLimit &&
          other.lowBalanceThreshold == this.lowBalanceThreshold);
}

class WalletsCompanion extends UpdateCompanion<DbWallet> {
  final Value<int> id;
  final Value<String> name;
  final Value<bool> allowNegative;
  final Value<String> phone;
  final Value<double> dailyLimit;
  final Value<double> monthlyLimit;
  final Value<double> lowBalanceThreshold;
  const WalletsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.allowNegative = const Value.absent(),
    this.phone = const Value.absent(),
    this.dailyLimit = const Value.absent(),
    this.monthlyLimit = const Value.absent(),
    this.lowBalanceThreshold = const Value.absent(),
  });
  WalletsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.allowNegative = const Value.absent(),
    this.phone = const Value.absent(),
    required double dailyLimit,
    required double monthlyLimit,
    required double lowBalanceThreshold,
  }) : name = Value(name),
       dailyLimit = Value(dailyLimit),
       monthlyLimit = Value(monthlyLimit),
       lowBalanceThreshold = Value(lowBalanceThreshold);
  static Insertable<DbWallet> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<bool>? allowNegative,
    Expression<String>? phone,
    Expression<double>? dailyLimit,
    Expression<double>? monthlyLimit,
    Expression<double>? lowBalanceThreshold,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (allowNegative != null) 'allow_negative': allowNegative,
      if (phone != null) 'phone': phone,
      if (dailyLimit != null) 'daily_limit': dailyLimit,
      if (monthlyLimit != null) 'monthly_limit': monthlyLimit,
      if (lowBalanceThreshold != null)
        'low_balance_threshold': lowBalanceThreshold,
    });
  }

  WalletsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<bool>? allowNegative,
    Value<String>? phone,
    Value<double>? dailyLimit,
    Value<double>? monthlyLimit,
    Value<double>? lowBalanceThreshold,
  }) {
    return WalletsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      allowNegative: allowNegative ?? this.allowNegative,
      phone: phone ?? this.phone,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
      lowBalanceThreshold: lowBalanceThreshold ?? this.lowBalanceThreshold,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (allowNegative.present) {
      map['allow_negative'] = Variable<bool>(allowNegative.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (dailyLimit.present) {
      map['daily_limit'] = Variable<double>(dailyLimit.value);
    }
    if (monthlyLimit.present) {
      map['monthly_limit'] = Variable<double>(monthlyLimit.value);
    }
    if (lowBalanceThreshold.present) {
      map['low_balance_threshold'] = Variable<double>(
        lowBalanceThreshold.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WalletsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('allowNegative: $allowNegative, ')
          ..write('phone: $phone, ')
          ..write('dailyLimit: $dailyLimit, ')
          ..write('monthlyLimit: $monthlyLimit, ')
          ..write('lowBalanceThreshold: $lowBalanceThreshold')
          ..write(')'))
        .toString();
  }
}

class $TxnsTable extends Txns with TableInfo<$TxnsTable, DbTxn> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TxnsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryDateMeta = const VerificationMeta(
    'entryDate',
  );
  @override
  late final GeneratedColumn<DateTime> entryDate = GeneratedColumn<DateTime>(
    'entry_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _walletFromIdMeta = const VerificationMeta(
    'walletFromId',
  );
  @override
  late final GeneratedColumn<int> walletFromId = GeneratedColumn<int>(
    'wallet_from_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _walletToIdMeta = const VerificationMeta(
    'walletToId',
  );
  @override
  late final GeneratedColumn<int> walletToId = GeneratedColumn<int>(
    'wallet_to_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientFeeMeta = const VerificationMeta(
    'clientFee',
  );
  @override
  late final GeneratedColumn<double> clientFee = GeneratedColumn<double>(
    'client_fee',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _networkFeeMeta = const VerificationMeta(
    'networkFee',
  );
  @override
  late final GeneratedColumn<double> networkFee = GeneratedColumn<double>(
    'network_fee',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serviceNameMeta = const VerificationMeta(
    'serviceName',
  );
  @override
  late final GeneratedColumn<String> serviceName = GeneratedColumn<String>(
    'service_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referenceMeta = const VerificationMeta(
    'reference',
  );
  @override
  late final GeneratedColumn<String> reference = GeneratedColumn<String>(
    'reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _partyMeta = const VerificationMeta('party');
  @override
  late final GeneratedColumn<String> party = GeneratedColumn<String>(
    'party',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdRoleMeta = const VerificationMeta(
    'createdRole',
  );
  @override
  late final GeneratedColumn<String> createdRole = GeneratedColumn<String>(
    'created_role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    status,
    entryDate,
    walletFromId,
    walletToId,
    amount,
    clientFee,
    networkFee,
    mode,
    note,
    serviceName,
    reference,
    party,
    createdBy,
    createdRole,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'txns';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbTxn> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('entry_date')) {
      context.handle(
        _entryDateMeta,
        entryDate.isAcceptableOrUnknown(data['entry_date']!, _entryDateMeta),
      );
    } else if (isInserting) {
      context.missing(_entryDateMeta);
    }
    if (data.containsKey('wallet_from_id')) {
      context.handle(
        _walletFromIdMeta,
        walletFromId.isAcceptableOrUnknown(
          data['wallet_from_id']!,
          _walletFromIdMeta,
        ),
      );
    }
    if (data.containsKey('wallet_to_id')) {
      context.handle(
        _walletToIdMeta,
        walletToId.isAcceptableOrUnknown(
          data['wallet_to_id']!,
          _walletToIdMeta,
        ),
      );
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('client_fee')) {
      context.handle(
        _clientFeeMeta,
        clientFee.isAcceptableOrUnknown(data['client_fee']!, _clientFeeMeta),
      );
    } else if (isInserting) {
      context.missing(_clientFeeMeta);
    }
    if (data.containsKey('network_fee')) {
      context.handle(
        _networkFeeMeta,
        networkFee.isAcceptableOrUnknown(data['network_fee']!, _networkFeeMeta),
      );
    } else if (isInserting) {
      context.missing(_networkFeeMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('service_name')) {
      context.handle(
        _serviceNameMeta,
        serviceName.isAcceptableOrUnknown(
          data['service_name']!,
          _serviceNameMeta,
        ),
      );
    }
    if (data.containsKey('reference')) {
      context.handle(
        _referenceMeta,
        reference.isAcceptableOrUnknown(data['reference']!, _referenceMeta),
      );
    }
    if (data.containsKey('party')) {
      context.handle(
        _partyMeta,
        party.isAcceptableOrUnknown(data['party']!, _partyMeta),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    } else if (isInserting) {
      context.missing(_createdByMeta);
    }
    if (data.containsKey('created_role')) {
      context.handle(
        _createdRoleMeta,
        createdRole.isAcceptableOrUnknown(
          data['created_role']!,
          _createdRoleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdRoleMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DbTxn map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbTxn(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      entryDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}entry_date'],
      )!,
      walletFromId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wallet_from_id'],
      ),
      walletToId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wallet_to_id'],
      ),
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      clientFee: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}client_fee'],
      )!,
      networkFee: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}network_fee'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      serviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}service_name'],
      ),
      reference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference'],
      ),
      party: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}party'],
      ),
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
      createdRole: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_role'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TxnsTable createAlias(String alias) {
    return $TxnsTable(attachedDatabase, alias);
  }
}

class DbTxn extends DataClass implements Insertable<DbTxn> {
  final int id;
  final String kind;
  final String status;
  final DateTime entryDate;
  final int? walletFromId;
  final int? walletToId;
  final double amount;
  final double clientFee;
  final double networkFee;
  final String mode;
  final String? note;
  final String? serviceName;
  final String? reference;
  final String? party;
  final String createdBy;
  final String createdRole;
  final DateTime createdAt;
  const DbTxn({
    required this.id,
    required this.kind,
    required this.status,
    required this.entryDate,
    this.walletFromId,
    this.walletToId,
    required this.amount,
    required this.clientFee,
    required this.networkFee,
    required this.mode,
    this.note,
    this.serviceName,
    this.reference,
    this.party,
    required this.createdBy,
    required this.createdRole,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    map['status'] = Variable<String>(status);
    map['entry_date'] = Variable<DateTime>(entryDate);
    if (!nullToAbsent || walletFromId != null) {
      map['wallet_from_id'] = Variable<int>(walletFromId);
    }
    if (!nullToAbsent || walletToId != null) {
      map['wallet_to_id'] = Variable<int>(walletToId);
    }
    map['amount'] = Variable<double>(amount);
    map['client_fee'] = Variable<double>(clientFee);
    map['network_fee'] = Variable<double>(networkFee);
    map['mode'] = Variable<String>(mode);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || serviceName != null) {
      map['service_name'] = Variable<String>(serviceName);
    }
    if (!nullToAbsent || reference != null) {
      map['reference'] = Variable<String>(reference);
    }
    if (!nullToAbsent || party != null) {
      map['party'] = Variable<String>(party);
    }
    map['created_by'] = Variable<String>(createdBy);
    map['created_role'] = Variable<String>(createdRole);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TxnsCompanion toCompanion(bool nullToAbsent) {
    return TxnsCompanion(
      id: Value(id),
      kind: Value(kind),
      status: Value(status),
      entryDate: Value(entryDate),
      walletFromId: walletFromId == null && nullToAbsent
          ? const Value.absent()
          : Value(walletFromId),
      walletToId: walletToId == null && nullToAbsent
          ? const Value.absent()
          : Value(walletToId),
      amount: Value(amount),
      clientFee: Value(clientFee),
      networkFee: Value(networkFee),
      mode: Value(mode),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      serviceName: serviceName == null && nullToAbsent
          ? const Value.absent()
          : Value(serviceName),
      reference: reference == null && nullToAbsent
          ? const Value.absent()
          : Value(reference),
      party: party == null && nullToAbsent
          ? const Value.absent()
          : Value(party),
      createdBy: Value(createdBy),
      createdRole: Value(createdRole),
      createdAt: Value(createdAt),
    );
  }

  factory DbTxn.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbTxn(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      status: serializer.fromJson<String>(json['status']),
      entryDate: serializer.fromJson<DateTime>(json['entryDate']),
      walletFromId: serializer.fromJson<int?>(json['walletFromId']),
      walletToId: serializer.fromJson<int?>(json['walletToId']),
      amount: serializer.fromJson<double>(json['amount']),
      clientFee: serializer.fromJson<double>(json['clientFee']),
      networkFee: serializer.fromJson<double>(json['networkFee']),
      mode: serializer.fromJson<String>(json['mode']),
      note: serializer.fromJson<String?>(json['note']),
      serviceName: serializer.fromJson<String?>(json['serviceName']),
      reference: serializer.fromJson<String?>(json['reference']),
      party: serializer.fromJson<String?>(json['party']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
      createdRole: serializer.fromJson<String>(json['createdRole']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'status': serializer.toJson<String>(status),
      'entryDate': serializer.toJson<DateTime>(entryDate),
      'walletFromId': serializer.toJson<int?>(walletFromId),
      'walletToId': serializer.toJson<int?>(walletToId),
      'amount': serializer.toJson<double>(amount),
      'clientFee': serializer.toJson<double>(clientFee),
      'networkFee': serializer.toJson<double>(networkFee),
      'mode': serializer.toJson<String>(mode),
      'note': serializer.toJson<String?>(note),
      'serviceName': serializer.toJson<String?>(serviceName),
      'reference': serializer.toJson<String?>(reference),
      'party': serializer.toJson<String?>(party),
      'createdBy': serializer.toJson<String>(createdBy),
      'createdRole': serializer.toJson<String>(createdRole),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  DbTxn copyWith({
    int? id,
    String? kind,
    String? status,
    DateTime? entryDate,
    Value<int?> walletFromId = const Value.absent(),
    Value<int?> walletToId = const Value.absent(),
    double? amount,
    double? clientFee,
    double? networkFee,
    String? mode,
    Value<String?> note = const Value.absent(),
    Value<String?> serviceName = const Value.absent(),
    Value<String?> reference = const Value.absent(),
    Value<String?> party = const Value.absent(),
    String? createdBy,
    String? createdRole,
    DateTime? createdAt,
  }) => DbTxn(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    entryDate: entryDate ?? this.entryDate,
    walletFromId: walletFromId.present ? walletFromId.value : this.walletFromId,
    walletToId: walletToId.present ? walletToId.value : this.walletToId,
    amount: amount ?? this.amount,
    clientFee: clientFee ?? this.clientFee,
    networkFee: networkFee ?? this.networkFee,
    mode: mode ?? this.mode,
    note: note.present ? note.value : this.note,
    serviceName: serviceName.present ? serviceName.value : this.serviceName,
    reference: reference.present ? reference.value : this.reference,
    party: party.present ? party.value : this.party,
    createdBy: createdBy ?? this.createdBy,
    createdRole: createdRole ?? this.createdRole,
    createdAt: createdAt ?? this.createdAt,
  );
  DbTxn copyWithCompanion(TxnsCompanion data) {
    return DbTxn(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      status: data.status.present ? data.status.value : this.status,
      entryDate: data.entryDate.present ? data.entryDate.value : this.entryDate,
      walletFromId: data.walletFromId.present
          ? data.walletFromId.value
          : this.walletFromId,
      walletToId: data.walletToId.present
          ? data.walletToId.value
          : this.walletToId,
      amount: data.amount.present ? data.amount.value : this.amount,
      clientFee: data.clientFee.present ? data.clientFee.value : this.clientFee,
      networkFee: data.networkFee.present
          ? data.networkFee.value
          : this.networkFee,
      mode: data.mode.present ? data.mode.value : this.mode,
      note: data.note.present ? data.note.value : this.note,
      serviceName: data.serviceName.present
          ? data.serviceName.value
          : this.serviceName,
      reference: data.reference.present ? data.reference.value : this.reference,
      party: data.party.present ? data.party.value : this.party,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      createdRole: data.createdRole.present
          ? data.createdRole.value
          : this.createdRole,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbTxn(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('entryDate: $entryDate, ')
          ..write('walletFromId: $walletFromId, ')
          ..write('walletToId: $walletToId, ')
          ..write('amount: $amount, ')
          ..write('clientFee: $clientFee, ')
          ..write('networkFee: $networkFee, ')
          ..write('mode: $mode, ')
          ..write('note: $note, ')
          ..write('serviceName: $serviceName, ')
          ..write('reference: $reference, ')
          ..write('party: $party, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdRole: $createdRole, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    status,
    entryDate,
    walletFromId,
    walletToId,
    amount,
    clientFee,
    networkFee,
    mode,
    note,
    serviceName,
    reference,
    party,
    createdBy,
    createdRole,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbTxn &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.status == this.status &&
          other.entryDate == this.entryDate &&
          other.walletFromId == this.walletFromId &&
          other.walletToId == this.walletToId &&
          other.amount == this.amount &&
          other.clientFee == this.clientFee &&
          other.networkFee == this.networkFee &&
          other.mode == this.mode &&
          other.note == this.note &&
          other.serviceName == this.serviceName &&
          other.reference == this.reference &&
          other.party == this.party &&
          other.createdBy == this.createdBy &&
          other.createdRole == this.createdRole &&
          other.createdAt == this.createdAt);
}

class TxnsCompanion extends UpdateCompanion<DbTxn> {
  final Value<int> id;
  final Value<String> kind;
  final Value<String> status;
  final Value<DateTime> entryDate;
  final Value<int?> walletFromId;
  final Value<int?> walletToId;
  final Value<double> amount;
  final Value<double> clientFee;
  final Value<double> networkFee;
  final Value<String> mode;
  final Value<String?> note;
  final Value<String?> serviceName;
  final Value<String?> reference;
  final Value<String?> party;
  final Value<String> createdBy;
  final Value<String> createdRole;
  final Value<DateTime> createdAt;
  const TxnsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.status = const Value.absent(),
    this.entryDate = const Value.absent(),
    this.walletFromId = const Value.absent(),
    this.walletToId = const Value.absent(),
    this.amount = const Value.absent(),
    this.clientFee = const Value.absent(),
    this.networkFee = const Value.absent(),
    this.mode = const Value.absent(),
    this.note = const Value.absent(),
    this.serviceName = const Value.absent(),
    this.reference = const Value.absent(),
    this.party = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.createdRole = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TxnsCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    required String status,
    required DateTime entryDate,
    this.walletFromId = const Value.absent(),
    this.walletToId = const Value.absent(),
    required double amount,
    required double clientFee,
    required double networkFee,
    required String mode,
    this.note = const Value.absent(),
    this.serviceName = const Value.absent(),
    this.reference = const Value.absent(),
    this.party = const Value.absent(),
    required String createdBy,
    required String createdRole,
    required DateTime createdAt,
  }) : kind = Value(kind),
       status = Value(status),
       entryDate = Value(entryDate),
       amount = Value(amount),
       clientFee = Value(clientFee),
       networkFee = Value(networkFee),
       mode = Value(mode),
       createdBy = Value(createdBy),
       createdRole = Value(createdRole),
       createdAt = Value(createdAt);
  static Insertable<DbTxn> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? status,
    Expression<DateTime>? entryDate,
    Expression<int>? walletFromId,
    Expression<int>? walletToId,
    Expression<double>? amount,
    Expression<double>? clientFee,
    Expression<double>? networkFee,
    Expression<String>? mode,
    Expression<String>? note,
    Expression<String>? serviceName,
    Expression<String>? reference,
    Expression<String>? party,
    Expression<String>? createdBy,
    Expression<String>? createdRole,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
      if (entryDate != null) 'entry_date': entryDate,
      if (walletFromId != null) 'wallet_from_id': walletFromId,
      if (walletToId != null) 'wallet_to_id': walletToId,
      if (amount != null) 'amount': amount,
      if (clientFee != null) 'client_fee': clientFee,
      if (networkFee != null) 'network_fee': networkFee,
      if (mode != null) 'mode': mode,
      if (note != null) 'note': note,
      if (serviceName != null) 'service_name': serviceName,
      if (reference != null) 'reference': reference,
      if (party != null) 'party': party,
      if (createdBy != null) 'created_by': createdBy,
      if (createdRole != null) 'created_role': createdRole,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TxnsCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<String>? status,
    Value<DateTime>? entryDate,
    Value<int?>? walletFromId,
    Value<int?>? walletToId,
    Value<double>? amount,
    Value<double>? clientFee,
    Value<double>? networkFee,
    Value<String>? mode,
    Value<String?>? note,
    Value<String?>? serviceName,
    Value<String?>? reference,
    Value<String?>? party,
    Value<String>? createdBy,
    Value<String>? createdRole,
    Value<DateTime>? createdAt,
  }) {
    return TxnsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      entryDate: entryDate ?? this.entryDate,
      walletFromId: walletFromId ?? this.walletFromId,
      walletToId: walletToId ?? this.walletToId,
      amount: amount ?? this.amount,
      clientFee: clientFee ?? this.clientFee,
      networkFee: networkFee ?? this.networkFee,
      mode: mode ?? this.mode,
      note: note ?? this.note,
      serviceName: serviceName ?? this.serviceName,
      reference: reference ?? this.reference,
      party: party ?? this.party,
      createdBy: createdBy ?? this.createdBy,
      createdRole: createdRole ?? this.createdRole,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (entryDate.present) {
      map['entry_date'] = Variable<DateTime>(entryDate.value);
    }
    if (walletFromId.present) {
      map['wallet_from_id'] = Variable<int>(walletFromId.value);
    }
    if (walletToId.present) {
      map['wallet_to_id'] = Variable<int>(walletToId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (clientFee.present) {
      map['client_fee'] = Variable<double>(clientFee.value);
    }
    if (networkFee.present) {
      map['network_fee'] = Variable<double>(networkFee.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (serviceName.present) {
      map['service_name'] = Variable<String>(serviceName.value);
    }
    if (reference.present) {
      map['reference'] = Variable<String>(reference.value);
    }
    if (party.present) {
      map['party'] = Variable<String>(party.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (createdRole.present) {
      map['created_role'] = Variable<String>(createdRole.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TxnsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('entryDate: $entryDate, ')
          ..write('walletFromId: $walletFromId, ')
          ..write('walletToId: $walletToId, ')
          ..write('amount: $amount, ')
          ..write('clientFee: $clientFee, ')
          ..write('networkFee: $networkFee, ')
          ..write('mode: $mode, ')
          ..write('note: $note, ')
          ..write('serviceName: $serviceName, ')
          ..write('reference: $reference, ')
          ..write('party: $party, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdRole: $createdRole, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ClaimsTable extends Claims with TableInfo<$ClaimsTable, DbClaim> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClaimsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _partyMeta = const VerificationMeta('party');
  @override
  late final GeneratedColumn<String> party = GeneratedColumn<String>(
    'party',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _entryDateMeta = const VerificationMeta(
    'entryDate',
  );
  @override
  late final GeneratedColumn<DateTime> entryDate = GeneratedColumn<DateTime>(
    'entry_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _settledTxnIdMeta = const VerificationMeta(
    'settledTxnId',
  );
  @override
  late final GeneratedColumn<int> settledTxnId = GeneratedColumn<int>(
    'settled_txn_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _settledDateMeta = const VerificationMeta(
    'settledDate',
  );
  @override
  late final GeneratedColumn<DateTime> settledDate = GeneratedColumn<DateTime>(
    'settled_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceTxnIdMeta = const VerificationMeta(
    'sourceTxnId',
  );
  @override
  late final GeneratedColumn<int> sourceTxnId = GeneratedColumn<int>(
    'source_txn_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    party,
    amount,
    note,
    entryDate,
    status,
    settledTxnId,
    settledDate,
    sourceTxnId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'claims';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbClaim> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('party')) {
      context.handle(
        _partyMeta,
        party.isAcceptableOrUnknown(data['party']!, _partyMeta),
      );
    } else if (isInserting) {
      context.missing(_partyMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('entry_date')) {
      context.handle(
        _entryDateMeta,
        entryDate.isAcceptableOrUnknown(data['entry_date']!, _entryDateMeta),
      );
    } else if (isInserting) {
      context.missing(_entryDateMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('settled_txn_id')) {
      context.handle(
        _settledTxnIdMeta,
        settledTxnId.isAcceptableOrUnknown(
          data['settled_txn_id']!,
          _settledTxnIdMeta,
        ),
      );
    }
    if (data.containsKey('settled_date')) {
      context.handle(
        _settledDateMeta,
        settledDate.isAcceptableOrUnknown(
          data['settled_date']!,
          _settledDateMeta,
        ),
      );
    }
    if (data.containsKey('source_txn_id')) {
      context.handle(
        _sourceTxnIdMeta,
        sourceTxnId.isAcceptableOrUnknown(
          data['source_txn_id']!,
          _sourceTxnIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DbClaim map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbClaim(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      party: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}party'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      entryDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}entry_date'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      settledTxnId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}settled_txn_id'],
      ),
      settledDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}settled_date'],
      ),
      sourceTxnId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_txn_id'],
      ),
    );
  }

  @override
  $ClaimsTable createAlias(String alias) {
    return $ClaimsTable(attachedDatabase, alias);
  }
}

class DbClaim extends DataClass implements Insertable<DbClaim> {
  final int id;
  final String type;
  final String party;
  final double amount;
  final String? note;
  final DateTime entryDate;
  final String status;
  final int? settledTxnId;
  final DateTime? settledDate;
  final int? sourceTxnId;
  const DbClaim({
    required this.id,
    required this.type,
    required this.party,
    required this.amount,
    this.note,
    required this.entryDate,
    required this.status,
    this.settledTxnId,
    this.settledDate,
    this.sourceTxnId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['type'] = Variable<String>(type);
    map['party'] = Variable<String>(party);
    map['amount'] = Variable<double>(amount);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['entry_date'] = Variable<DateTime>(entryDate);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || settledTxnId != null) {
      map['settled_txn_id'] = Variable<int>(settledTxnId);
    }
    if (!nullToAbsent || settledDate != null) {
      map['settled_date'] = Variable<DateTime>(settledDate);
    }
    if (!nullToAbsent || sourceTxnId != null) {
      map['source_txn_id'] = Variable<int>(sourceTxnId);
    }
    return map;
  }

  ClaimsCompanion toCompanion(bool nullToAbsent) {
    return ClaimsCompanion(
      id: Value(id),
      type: Value(type),
      party: Value(party),
      amount: Value(amount),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      entryDate: Value(entryDate),
      status: Value(status),
      settledTxnId: settledTxnId == null && nullToAbsent
          ? const Value.absent()
          : Value(settledTxnId),
      settledDate: settledDate == null && nullToAbsent
          ? const Value.absent()
          : Value(settledDate),
      sourceTxnId: sourceTxnId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceTxnId),
    );
  }

  factory DbClaim.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbClaim(
      id: serializer.fromJson<int>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      party: serializer.fromJson<String>(json['party']),
      amount: serializer.fromJson<double>(json['amount']),
      note: serializer.fromJson<String?>(json['note']),
      entryDate: serializer.fromJson<DateTime>(json['entryDate']),
      status: serializer.fromJson<String>(json['status']),
      settledTxnId: serializer.fromJson<int?>(json['settledTxnId']),
      settledDate: serializer.fromJson<DateTime?>(json['settledDate']),
      sourceTxnId: serializer.fromJson<int?>(json['sourceTxnId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<String>(type),
      'party': serializer.toJson<String>(party),
      'amount': serializer.toJson<double>(amount),
      'note': serializer.toJson<String?>(note),
      'entryDate': serializer.toJson<DateTime>(entryDate),
      'status': serializer.toJson<String>(status),
      'settledTxnId': serializer.toJson<int?>(settledTxnId),
      'settledDate': serializer.toJson<DateTime?>(settledDate),
      'sourceTxnId': serializer.toJson<int?>(sourceTxnId),
    };
  }

  DbClaim copyWith({
    int? id,
    String? type,
    String? party,
    double? amount,
    Value<String?> note = const Value.absent(),
    DateTime? entryDate,
    String? status,
    Value<int?> settledTxnId = const Value.absent(),
    Value<DateTime?> settledDate = const Value.absent(),
    Value<int?> sourceTxnId = const Value.absent(),
  }) => DbClaim(
    id: id ?? this.id,
    type: type ?? this.type,
    party: party ?? this.party,
    amount: amount ?? this.amount,
    note: note.present ? note.value : this.note,
    entryDate: entryDate ?? this.entryDate,
    status: status ?? this.status,
    settledTxnId: settledTxnId.present ? settledTxnId.value : this.settledTxnId,
    settledDate: settledDate.present ? settledDate.value : this.settledDate,
    sourceTxnId: sourceTxnId.present ? sourceTxnId.value : this.sourceTxnId,
  );
  DbClaim copyWithCompanion(ClaimsCompanion data) {
    return DbClaim(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      party: data.party.present ? data.party.value : this.party,
      amount: data.amount.present ? data.amount.value : this.amount,
      note: data.note.present ? data.note.value : this.note,
      entryDate: data.entryDate.present ? data.entryDate.value : this.entryDate,
      status: data.status.present ? data.status.value : this.status,
      settledTxnId: data.settledTxnId.present
          ? data.settledTxnId.value
          : this.settledTxnId,
      settledDate: data.settledDate.present
          ? data.settledDate.value
          : this.settledDate,
      sourceTxnId: data.sourceTxnId.present
          ? data.sourceTxnId.value
          : this.sourceTxnId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbClaim(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('party: $party, ')
          ..write('amount: $amount, ')
          ..write('note: $note, ')
          ..write('entryDate: $entryDate, ')
          ..write('status: $status, ')
          ..write('settledTxnId: $settledTxnId, ')
          ..write('settledDate: $settledDate, ')
          ..write('sourceTxnId: $sourceTxnId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    party,
    amount,
    note,
    entryDate,
    status,
    settledTxnId,
    settledDate,
    sourceTxnId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbClaim &&
          other.id == this.id &&
          other.type == this.type &&
          other.party == this.party &&
          other.amount == this.amount &&
          other.note == this.note &&
          other.entryDate == this.entryDate &&
          other.status == this.status &&
          other.settledTxnId == this.settledTxnId &&
          other.settledDate == this.settledDate &&
          other.sourceTxnId == this.sourceTxnId);
}

class ClaimsCompanion extends UpdateCompanion<DbClaim> {
  final Value<int> id;
  final Value<String> type;
  final Value<String> party;
  final Value<double> amount;
  final Value<String?> note;
  final Value<DateTime> entryDate;
  final Value<String> status;
  final Value<int?> settledTxnId;
  final Value<DateTime?> settledDate;
  final Value<int?> sourceTxnId;
  const ClaimsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.party = const Value.absent(),
    this.amount = const Value.absent(),
    this.note = const Value.absent(),
    this.entryDate = const Value.absent(),
    this.status = const Value.absent(),
    this.settledTxnId = const Value.absent(),
    this.settledDate = const Value.absent(),
    this.sourceTxnId = const Value.absent(),
  });
  ClaimsCompanion.insert({
    this.id = const Value.absent(),
    required String type,
    required String party,
    required double amount,
    this.note = const Value.absent(),
    required DateTime entryDate,
    required String status,
    this.settledTxnId = const Value.absent(),
    this.settledDate = const Value.absent(),
    this.sourceTxnId = const Value.absent(),
  }) : type = Value(type),
       party = Value(party),
       amount = Value(amount),
       entryDate = Value(entryDate),
       status = Value(status);
  static Insertable<DbClaim> custom({
    Expression<int>? id,
    Expression<String>? type,
    Expression<String>? party,
    Expression<double>? amount,
    Expression<String>? note,
    Expression<DateTime>? entryDate,
    Expression<String>? status,
    Expression<int>? settledTxnId,
    Expression<DateTime>? settledDate,
    Expression<int>? sourceTxnId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (party != null) 'party': party,
      if (amount != null) 'amount': amount,
      if (note != null) 'note': note,
      if (entryDate != null) 'entry_date': entryDate,
      if (status != null) 'status': status,
      if (settledTxnId != null) 'settled_txn_id': settledTxnId,
      if (settledDate != null) 'settled_date': settledDate,
      if (sourceTxnId != null) 'source_txn_id': sourceTxnId,
    });
  }

  ClaimsCompanion copyWith({
    Value<int>? id,
    Value<String>? type,
    Value<String>? party,
    Value<double>? amount,
    Value<String?>? note,
    Value<DateTime>? entryDate,
    Value<String>? status,
    Value<int?>? settledTxnId,
    Value<DateTime?>? settledDate,
    Value<int?>? sourceTxnId,
  }) {
    return ClaimsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      party: party ?? this.party,
      amount: amount ?? this.amount,
      note: note ?? this.note,
      entryDate: entryDate ?? this.entryDate,
      status: status ?? this.status,
      settledTxnId: settledTxnId ?? this.settledTxnId,
      settledDate: settledDate ?? this.settledDate,
      sourceTxnId: sourceTxnId ?? this.sourceTxnId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (party.present) {
      map['party'] = Variable<String>(party.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (entryDate.present) {
      map['entry_date'] = Variable<DateTime>(entryDate.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (settledTxnId.present) {
      map['settled_txn_id'] = Variable<int>(settledTxnId.value);
    }
    if (settledDate.present) {
      map['settled_date'] = Variable<DateTime>(settledDate.value);
    }
    if (sourceTxnId.present) {
      map['source_txn_id'] = Variable<int>(sourceTxnId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClaimsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('party: $party, ')
          ..write('amount: $amount, ')
          ..write('note: $note, ')
          ..write('entryDate: $entryDate, ')
          ..write('status: $status, ')
          ..write('settledTxnId: $settledTxnId, ')
          ..write('settledDate: $settledDate, ')
          ..write('sourceTxnId: $sourceTxnId')
          ..write(')'))
        .toString();
  }
}

class $DailyClosesTable extends DailyCloses
    with TableInfo<$DailyClosesTable, DbDailyClose> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyClosesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateKeyMeta = const VerificationMeta(
    'dateKey',
  );
  @override
  late final GeneratedColumn<String> dateKey = GeneratedColumn<String>(
    'date_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _closedAtMeta = const VerificationMeta(
    'closedAt',
  );
  @override
  late final GeneratedColumn<DateTime> closedAt = GeneratedColumn<DateTime>(
    'closed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _drawerBalanceMeta = const VerificationMeta(
    'drawerBalance',
  );
  @override
  late final GeneratedColumn<double> drawerBalance = GeneratedColumn<double>(
    'drawer_balance',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _walletsTotalMeta = const VerificationMeta(
    'walletsTotal',
  );
  @override
  late final GeneratedColumn<double> walletsTotal = GeneratedColumn<double>(
    'wallets_total',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _treasuryTotalMeta = const VerificationMeta(
    'treasuryTotal',
  );
  @override
  late final GeneratedColumn<double> treasuryTotal = GeneratedColumn<double>(
    'treasury_total',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profitTotalMeta = const VerificationMeta(
    'profitTotal',
  );
  @override
  late final GeneratedColumn<double> profitTotal = GeneratedColumn<double>(
    'profit_total',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profitTransferMeta = const VerificationMeta(
    'profitTransfer',
  );
  @override
  late final GeneratedColumn<double> profitTransfer = GeneratedColumn<double>(
    'profit_transfer',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profitReceiveMeta = const VerificationMeta(
    'profitReceive',
  );
  @override
  late final GeneratedColumn<double> profitReceive = GeneratedColumn<double>(
    'profit_receive',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profitFawryMeta = const VerificationMeta(
    'profitFawry',
  );
  @override
  late final GeneratedColumn<double> profitFawry = GeneratedColumn<double>(
    'profit_fawry',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inflowMeta = const VerificationMeta('inflow');
  @override
  late final GeneratedColumn<double> inflow = GeneratedColumn<double>(
    'inflow',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outflowMeta = const VerificationMeta(
    'outflow',
  );
  @override
  late final GeneratedColumn<double> outflow = GeneratedColumn<double>(
    'outflow',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _netMeta = const VerificationMeta('net');
  @override
  late final GeneratedColumn<double> net = GeneratedColumn<double>(
    'net',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transferCountMeta = const VerificationMeta(
    'transferCount',
  );
  @override
  late final GeneratedColumn<int> transferCount = GeneratedColumn<int>(
    'transfer_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receiveCountMeta = const VerificationMeta(
    'receiveCount',
  );
  @override
  late final GeneratedColumn<int> receiveCount = GeneratedColumn<int>(
    'receive_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fawryCashCountMeta = const VerificationMeta(
    'fawryCashCount',
  );
  @override
  late final GeneratedColumn<int> fawryCashCount = GeneratedColumn<int>(
    'fawry_cash_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fawryCreditCountMeta = const VerificationMeta(
    'fawryCreditCount',
  );
  @override
  late final GeneratedColumn<int> fawryCreditCount = GeneratedColumn<int>(
    'fawry_credit_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expenseCountMeta = const VerificationMeta(
    'expenseCount',
  );
  @override
  late final GeneratedColumn<int> expenseCount = GeneratedColumn<int>(
    'expense_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _claimCollectCountMeta = const VerificationMeta(
    'claimCollectCount',
  );
  @override
  late final GeneratedColumn<int> claimCollectCount = GeneratedColumn<int>(
    'claim_collect_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _claimPayCountMeta = const VerificationMeta(
    'claimPayCount',
  );
  @override
  late final GeneratedColumn<int> claimPayCount = GeneratedColumn<int>(
    'claim_pay_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pendingCountMeta = const VerificationMeta(
    'pendingCount',
  );
  @override
  late final GeneratedColumn<int> pendingCount = GeneratedColumn<int>(
    'pending_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    dateKey,
    closedAt,
    drawerBalance,
    walletsTotal,
    treasuryTotal,
    profitTotal,
    profitTransfer,
    profitReceive,
    profitFawry,
    inflow,
    outflow,
    net,
    transferCount,
    receiveCount,
    fawryCashCount,
    fawryCreditCount,
    expenseCount,
    claimCollectCount,
    claimPayCount,
    pendingCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_closes';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbDailyClose> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date_key')) {
      context.handle(
        _dateKeyMeta,
        dateKey.isAcceptableOrUnknown(data['date_key']!, _dateKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_dateKeyMeta);
    }
    if (data.containsKey('closed_at')) {
      context.handle(
        _closedAtMeta,
        closedAt.isAcceptableOrUnknown(data['closed_at']!, _closedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_closedAtMeta);
    }
    if (data.containsKey('drawer_balance')) {
      context.handle(
        _drawerBalanceMeta,
        drawerBalance.isAcceptableOrUnknown(
          data['drawer_balance']!,
          _drawerBalanceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_drawerBalanceMeta);
    }
    if (data.containsKey('wallets_total')) {
      context.handle(
        _walletsTotalMeta,
        walletsTotal.isAcceptableOrUnknown(
          data['wallets_total']!,
          _walletsTotalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_walletsTotalMeta);
    }
    if (data.containsKey('treasury_total')) {
      context.handle(
        _treasuryTotalMeta,
        treasuryTotal.isAcceptableOrUnknown(
          data['treasury_total']!,
          _treasuryTotalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_treasuryTotalMeta);
    }
    if (data.containsKey('profit_total')) {
      context.handle(
        _profitTotalMeta,
        profitTotal.isAcceptableOrUnknown(
          data['profit_total']!,
          _profitTotalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_profitTotalMeta);
    }
    if (data.containsKey('profit_transfer')) {
      context.handle(
        _profitTransferMeta,
        profitTransfer.isAcceptableOrUnknown(
          data['profit_transfer']!,
          _profitTransferMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_profitTransferMeta);
    }
    if (data.containsKey('profit_receive')) {
      context.handle(
        _profitReceiveMeta,
        profitReceive.isAcceptableOrUnknown(
          data['profit_receive']!,
          _profitReceiveMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_profitReceiveMeta);
    }
    if (data.containsKey('profit_fawry')) {
      context.handle(
        _profitFawryMeta,
        profitFawry.isAcceptableOrUnknown(
          data['profit_fawry']!,
          _profitFawryMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_profitFawryMeta);
    }
    if (data.containsKey('inflow')) {
      context.handle(
        _inflowMeta,
        inflow.isAcceptableOrUnknown(data['inflow']!, _inflowMeta),
      );
    } else if (isInserting) {
      context.missing(_inflowMeta);
    }
    if (data.containsKey('outflow')) {
      context.handle(
        _outflowMeta,
        outflow.isAcceptableOrUnknown(data['outflow']!, _outflowMeta),
      );
    } else if (isInserting) {
      context.missing(_outflowMeta);
    }
    if (data.containsKey('net')) {
      context.handle(
        _netMeta,
        net.isAcceptableOrUnknown(data['net']!, _netMeta),
      );
    } else if (isInserting) {
      context.missing(_netMeta);
    }
    if (data.containsKey('transfer_count')) {
      context.handle(
        _transferCountMeta,
        transferCount.isAcceptableOrUnknown(
          data['transfer_count']!,
          _transferCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transferCountMeta);
    }
    if (data.containsKey('receive_count')) {
      context.handle(
        _receiveCountMeta,
        receiveCount.isAcceptableOrUnknown(
          data['receive_count']!,
          _receiveCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receiveCountMeta);
    }
    if (data.containsKey('fawry_cash_count')) {
      context.handle(
        _fawryCashCountMeta,
        fawryCashCount.isAcceptableOrUnknown(
          data['fawry_cash_count']!,
          _fawryCashCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fawryCashCountMeta);
    }
    if (data.containsKey('fawry_credit_count')) {
      context.handle(
        _fawryCreditCountMeta,
        fawryCreditCount.isAcceptableOrUnknown(
          data['fawry_credit_count']!,
          _fawryCreditCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fawryCreditCountMeta);
    }
    if (data.containsKey('expense_count')) {
      context.handle(
        _expenseCountMeta,
        expenseCount.isAcceptableOrUnknown(
          data['expense_count']!,
          _expenseCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_expenseCountMeta);
    }
    if (data.containsKey('claim_collect_count')) {
      context.handle(
        _claimCollectCountMeta,
        claimCollectCount.isAcceptableOrUnknown(
          data['claim_collect_count']!,
          _claimCollectCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_claimCollectCountMeta);
    }
    if (data.containsKey('claim_pay_count')) {
      context.handle(
        _claimPayCountMeta,
        claimPayCount.isAcceptableOrUnknown(
          data['claim_pay_count']!,
          _claimPayCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_claimPayCountMeta);
    }
    if (data.containsKey('pending_count')) {
      context.handle(
        _pendingCountMeta,
        pendingCount.isAcceptableOrUnknown(
          data['pending_count']!,
          _pendingCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_pendingCountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DbDailyClose map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbDailyClose(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      dateKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date_key'],
      )!,
      closedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}closed_at'],
      )!,
      drawerBalance: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}drawer_balance'],
      )!,
      walletsTotal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}wallets_total'],
      )!,
      treasuryTotal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}treasury_total'],
      )!,
      profitTotal: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}profit_total'],
      )!,
      profitTransfer: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}profit_transfer'],
      )!,
      profitReceive: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}profit_receive'],
      )!,
      profitFawry: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}profit_fawry'],
      )!,
      inflow: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}inflow'],
      )!,
      outflow: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}outflow'],
      )!,
      net: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}net'],
      )!,
      transferCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}transfer_count'],
      )!,
      receiveCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}receive_count'],
      )!,
      fawryCashCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fawry_cash_count'],
      )!,
      fawryCreditCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fawry_credit_count'],
      )!,
      expenseCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expense_count'],
      )!,
      claimCollectCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}claim_collect_count'],
      )!,
      claimPayCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}claim_pay_count'],
      )!,
      pendingCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pending_count'],
      )!,
    );
  }

  @override
  $DailyClosesTable createAlias(String alias) {
    return $DailyClosesTable(attachedDatabase, alias);
  }
}

class DbDailyClose extends DataClass implements Insertable<DbDailyClose> {
  final int id;
  final String dateKey;
  final DateTime closedAt;
  final double drawerBalance;
  final double walletsTotal;
  final double treasuryTotal;
  final double profitTotal;
  final double profitTransfer;
  final double profitReceive;
  final double profitFawry;
  final double inflow;
  final double outflow;
  final double net;
  final int transferCount;
  final int receiveCount;
  final int fawryCashCount;
  final int fawryCreditCount;
  final int expenseCount;
  final int claimCollectCount;
  final int claimPayCount;
  final int pendingCount;
  const DbDailyClose({
    required this.id,
    required this.dateKey,
    required this.closedAt,
    required this.drawerBalance,
    required this.walletsTotal,
    required this.treasuryTotal,
    required this.profitTotal,
    required this.profitTransfer,
    required this.profitReceive,
    required this.profitFawry,
    required this.inflow,
    required this.outflow,
    required this.net,
    required this.transferCount,
    required this.receiveCount,
    required this.fawryCashCount,
    required this.fawryCreditCount,
    required this.expenseCount,
    required this.claimCollectCount,
    required this.claimPayCount,
    required this.pendingCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['date_key'] = Variable<String>(dateKey);
    map['closed_at'] = Variable<DateTime>(closedAt);
    map['drawer_balance'] = Variable<double>(drawerBalance);
    map['wallets_total'] = Variable<double>(walletsTotal);
    map['treasury_total'] = Variable<double>(treasuryTotal);
    map['profit_total'] = Variable<double>(profitTotal);
    map['profit_transfer'] = Variable<double>(profitTransfer);
    map['profit_receive'] = Variable<double>(profitReceive);
    map['profit_fawry'] = Variable<double>(profitFawry);
    map['inflow'] = Variable<double>(inflow);
    map['outflow'] = Variable<double>(outflow);
    map['net'] = Variable<double>(net);
    map['transfer_count'] = Variable<int>(transferCount);
    map['receive_count'] = Variable<int>(receiveCount);
    map['fawry_cash_count'] = Variable<int>(fawryCashCount);
    map['fawry_credit_count'] = Variable<int>(fawryCreditCount);
    map['expense_count'] = Variable<int>(expenseCount);
    map['claim_collect_count'] = Variable<int>(claimCollectCount);
    map['claim_pay_count'] = Variable<int>(claimPayCount);
    map['pending_count'] = Variable<int>(pendingCount);
    return map;
  }

  DailyClosesCompanion toCompanion(bool nullToAbsent) {
    return DailyClosesCompanion(
      id: Value(id),
      dateKey: Value(dateKey),
      closedAt: Value(closedAt),
      drawerBalance: Value(drawerBalance),
      walletsTotal: Value(walletsTotal),
      treasuryTotal: Value(treasuryTotal),
      profitTotal: Value(profitTotal),
      profitTransfer: Value(profitTransfer),
      profitReceive: Value(profitReceive),
      profitFawry: Value(profitFawry),
      inflow: Value(inflow),
      outflow: Value(outflow),
      net: Value(net),
      transferCount: Value(transferCount),
      receiveCount: Value(receiveCount),
      fawryCashCount: Value(fawryCashCount),
      fawryCreditCount: Value(fawryCreditCount),
      expenseCount: Value(expenseCount),
      claimCollectCount: Value(claimCollectCount),
      claimPayCount: Value(claimPayCount),
      pendingCount: Value(pendingCount),
    );
  }

  factory DbDailyClose.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbDailyClose(
      id: serializer.fromJson<int>(json['id']),
      dateKey: serializer.fromJson<String>(json['dateKey']),
      closedAt: serializer.fromJson<DateTime>(json['closedAt']),
      drawerBalance: serializer.fromJson<double>(json['drawerBalance']),
      walletsTotal: serializer.fromJson<double>(json['walletsTotal']),
      treasuryTotal: serializer.fromJson<double>(json['treasuryTotal']),
      profitTotal: serializer.fromJson<double>(json['profitTotal']),
      profitTransfer: serializer.fromJson<double>(json['profitTransfer']),
      profitReceive: serializer.fromJson<double>(json['profitReceive']),
      profitFawry: serializer.fromJson<double>(json['profitFawry']),
      inflow: serializer.fromJson<double>(json['inflow']),
      outflow: serializer.fromJson<double>(json['outflow']),
      net: serializer.fromJson<double>(json['net']),
      transferCount: serializer.fromJson<int>(json['transferCount']),
      receiveCount: serializer.fromJson<int>(json['receiveCount']),
      fawryCashCount: serializer.fromJson<int>(json['fawryCashCount']),
      fawryCreditCount: serializer.fromJson<int>(json['fawryCreditCount']),
      expenseCount: serializer.fromJson<int>(json['expenseCount']),
      claimCollectCount: serializer.fromJson<int>(json['claimCollectCount']),
      claimPayCount: serializer.fromJson<int>(json['claimPayCount']),
      pendingCount: serializer.fromJson<int>(json['pendingCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'dateKey': serializer.toJson<String>(dateKey),
      'closedAt': serializer.toJson<DateTime>(closedAt),
      'drawerBalance': serializer.toJson<double>(drawerBalance),
      'walletsTotal': serializer.toJson<double>(walletsTotal),
      'treasuryTotal': serializer.toJson<double>(treasuryTotal),
      'profitTotal': serializer.toJson<double>(profitTotal),
      'profitTransfer': serializer.toJson<double>(profitTransfer),
      'profitReceive': serializer.toJson<double>(profitReceive),
      'profitFawry': serializer.toJson<double>(profitFawry),
      'inflow': serializer.toJson<double>(inflow),
      'outflow': serializer.toJson<double>(outflow),
      'net': serializer.toJson<double>(net),
      'transferCount': serializer.toJson<int>(transferCount),
      'receiveCount': serializer.toJson<int>(receiveCount),
      'fawryCashCount': serializer.toJson<int>(fawryCashCount),
      'fawryCreditCount': serializer.toJson<int>(fawryCreditCount),
      'expenseCount': serializer.toJson<int>(expenseCount),
      'claimCollectCount': serializer.toJson<int>(claimCollectCount),
      'claimPayCount': serializer.toJson<int>(claimPayCount),
      'pendingCount': serializer.toJson<int>(pendingCount),
    };
  }

  DbDailyClose copyWith({
    int? id,
    String? dateKey,
    DateTime? closedAt,
    double? drawerBalance,
    double? walletsTotal,
    double? treasuryTotal,
    double? profitTotal,
    double? profitTransfer,
    double? profitReceive,
    double? profitFawry,
    double? inflow,
    double? outflow,
    double? net,
    int? transferCount,
    int? receiveCount,
    int? fawryCashCount,
    int? fawryCreditCount,
    int? expenseCount,
    int? claimCollectCount,
    int? claimPayCount,
    int? pendingCount,
  }) => DbDailyClose(
    id: id ?? this.id,
    dateKey: dateKey ?? this.dateKey,
    closedAt: closedAt ?? this.closedAt,
    drawerBalance: drawerBalance ?? this.drawerBalance,
    walletsTotal: walletsTotal ?? this.walletsTotal,
    treasuryTotal: treasuryTotal ?? this.treasuryTotal,
    profitTotal: profitTotal ?? this.profitTotal,
    profitTransfer: profitTransfer ?? this.profitTransfer,
    profitReceive: profitReceive ?? this.profitReceive,
    profitFawry: profitFawry ?? this.profitFawry,
    inflow: inflow ?? this.inflow,
    outflow: outflow ?? this.outflow,
    net: net ?? this.net,
    transferCount: transferCount ?? this.transferCount,
    receiveCount: receiveCount ?? this.receiveCount,
    fawryCashCount: fawryCashCount ?? this.fawryCashCount,
    fawryCreditCount: fawryCreditCount ?? this.fawryCreditCount,
    expenseCount: expenseCount ?? this.expenseCount,
    claimCollectCount: claimCollectCount ?? this.claimCollectCount,
    claimPayCount: claimPayCount ?? this.claimPayCount,
    pendingCount: pendingCount ?? this.pendingCount,
  );
  DbDailyClose copyWithCompanion(DailyClosesCompanion data) {
    return DbDailyClose(
      id: data.id.present ? data.id.value : this.id,
      dateKey: data.dateKey.present ? data.dateKey.value : this.dateKey,
      closedAt: data.closedAt.present ? data.closedAt.value : this.closedAt,
      drawerBalance: data.drawerBalance.present
          ? data.drawerBalance.value
          : this.drawerBalance,
      walletsTotal: data.walletsTotal.present
          ? data.walletsTotal.value
          : this.walletsTotal,
      treasuryTotal: data.treasuryTotal.present
          ? data.treasuryTotal.value
          : this.treasuryTotal,
      profitTotal: data.profitTotal.present
          ? data.profitTotal.value
          : this.profitTotal,
      profitTransfer: data.profitTransfer.present
          ? data.profitTransfer.value
          : this.profitTransfer,
      profitReceive: data.profitReceive.present
          ? data.profitReceive.value
          : this.profitReceive,
      profitFawry: data.profitFawry.present
          ? data.profitFawry.value
          : this.profitFawry,
      inflow: data.inflow.present ? data.inflow.value : this.inflow,
      outflow: data.outflow.present ? data.outflow.value : this.outflow,
      net: data.net.present ? data.net.value : this.net,
      transferCount: data.transferCount.present
          ? data.transferCount.value
          : this.transferCount,
      receiveCount: data.receiveCount.present
          ? data.receiveCount.value
          : this.receiveCount,
      fawryCashCount: data.fawryCashCount.present
          ? data.fawryCashCount.value
          : this.fawryCashCount,
      fawryCreditCount: data.fawryCreditCount.present
          ? data.fawryCreditCount.value
          : this.fawryCreditCount,
      expenseCount: data.expenseCount.present
          ? data.expenseCount.value
          : this.expenseCount,
      claimCollectCount: data.claimCollectCount.present
          ? data.claimCollectCount.value
          : this.claimCollectCount,
      claimPayCount: data.claimPayCount.present
          ? data.claimPayCount.value
          : this.claimPayCount,
      pendingCount: data.pendingCount.present
          ? data.pendingCount.value
          : this.pendingCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbDailyClose(')
          ..write('id: $id, ')
          ..write('dateKey: $dateKey, ')
          ..write('closedAt: $closedAt, ')
          ..write('drawerBalance: $drawerBalance, ')
          ..write('walletsTotal: $walletsTotal, ')
          ..write('treasuryTotal: $treasuryTotal, ')
          ..write('profitTotal: $profitTotal, ')
          ..write('profitTransfer: $profitTransfer, ')
          ..write('profitReceive: $profitReceive, ')
          ..write('profitFawry: $profitFawry, ')
          ..write('inflow: $inflow, ')
          ..write('outflow: $outflow, ')
          ..write('net: $net, ')
          ..write('transferCount: $transferCount, ')
          ..write('receiveCount: $receiveCount, ')
          ..write('fawryCashCount: $fawryCashCount, ')
          ..write('fawryCreditCount: $fawryCreditCount, ')
          ..write('expenseCount: $expenseCount, ')
          ..write('claimCollectCount: $claimCollectCount, ')
          ..write('claimPayCount: $claimPayCount, ')
          ..write('pendingCount: $pendingCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    dateKey,
    closedAt,
    drawerBalance,
    walletsTotal,
    treasuryTotal,
    profitTotal,
    profitTransfer,
    profitReceive,
    profitFawry,
    inflow,
    outflow,
    net,
    transferCount,
    receiveCount,
    fawryCashCount,
    fawryCreditCount,
    expenseCount,
    claimCollectCount,
    claimPayCount,
    pendingCount,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbDailyClose &&
          other.id == this.id &&
          other.dateKey == this.dateKey &&
          other.closedAt == this.closedAt &&
          other.drawerBalance == this.drawerBalance &&
          other.walletsTotal == this.walletsTotal &&
          other.treasuryTotal == this.treasuryTotal &&
          other.profitTotal == this.profitTotal &&
          other.profitTransfer == this.profitTransfer &&
          other.profitReceive == this.profitReceive &&
          other.profitFawry == this.profitFawry &&
          other.inflow == this.inflow &&
          other.outflow == this.outflow &&
          other.net == this.net &&
          other.transferCount == this.transferCount &&
          other.receiveCount == this.receiveCount &&
          other.fawryCashCount == this.fawryCashCount &&
          other.fawryCreditCount == this.fawryCreditCount &&
          other.expenseCount == this.expenseCount &&
          other.claimCollectCount == this.claimCollectCount &&
          other.claimPayCount == this.claimPayCount &&
          other.pendingCount == this.pendingCount);
}

class DailyClosesCompanion extends UpdateCompanion<DbDailyClose> {
  final Value<int> id;
  final Value<String> dateKey;
  final Value<DateTime> closedAt;
  final Value<double> drawerBalance;
  final Value<double> walletsTotal;
  final Value<double> treasuryTotal;
  final Value<double> profitTotal;
  final Value<double> profitTransfer;
  final Value<double> profitReceive;
  final Value<double> profitFawry;
  final Value<double> inflow;
  final Value<double> outflow;
  final Value<double> net;
  final Value<int> transferCount;
  final Value<int> receiveCount;
  final Value<int> fawryCashCount;
  final Value<int> fawryCreditCount;
  final Value<int> expenseCount;
  final Value<int> claimCollectCount;
  final Value<int> claimPayCount;
  final Value<int> pendingCount;
  const DailyClosesCompanion({
    this.id = const Value.absent(),
    this.dateKey = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.drawerBalance = const Value.absent(),
    this.walletsTotal = const Value.absent(),
    this.treasuryTotal = const Value.absent(),
    this.profitTotal = const Value.absent(),
    this.profitTransfer = const Value.absent(),
    this.profitReceive = const Value.absent(),
    this.profitFawry = const Value.absent(),
    this.inflow = const Value.absent(),
    this.outflow = const Value.absent(),
    this.net = const Value.absent(),
    this.transferCount = const Value.absent(),
    this.receiveCount = const Value.absent(),
    this.fawryCashCount = const Value.absent(),
    this.fawryCreditCount = const Value.absent(),
    this.expenseCount = const Value.absent(),
    this.claimCollectCount = const Value.absent(),
    this.claimPayCount = const Value.absent(),
    this.pendingCount = const Value.absent(),
  });
  DailyClosesCompanion.insert({
    this.id = const Value.absent(),
    required String dateKey,
    required DateTime closedAt,
    required double drawerBalance,
    required double walletsTotal,
    required double treasuryTotal,
    required double profitTotal,
    required double profitTransfer,
    required double profitReceive,
    required double profitFawry,
    required double inflow,
    required double outflow,
    required double net,
    required int transferCount,
    required int receiveCount,
    required int fawryCashCount,
    required int fawryCreditCount,
    required int expenseCount,
    required int claimCollectCount,
    required int claimPayCount,
    required int pendingCount,
  }) : dateKey = Value(dateKey),
       closedAt = Value(closedAt),
       drawerBalance = Value(drawerBalance),
       walletsTotal = Value(walletsTotal),
       treasuryTotal = Value(treasuryTotal),
       profitTotal = Value(profitTotal),
       profitTransfer = Value(profitTransfer),
       profitReceive = Value(profitReceive),
       profitFawry = Value(profitFawry),
       inflow = Value(inflow),
       outflow = Value(outflow),
       net = Value(net),
       transferCount = Value(transferCount),
       receiveCount = Value(receiveCount),
       fawryCashCount = Value(fawryCashCount),
       fawryCreditCount = Value(fawryCreditCount),
       expenseCount = Value(expenseCount),
       claimCollectCount = Value(claimCollectCount),
       claimPayCount = Value(claimPayCount),
       pendingCount = Value(pendingCount);
  static Insertable<DbDailyClose> custom({
    Expression<int>? id,
    Expression<String>? dateKey,
    Expression<DateTime>? closedAt,
    Expression<double>? drawerBalance,
    Expression<double>? walletsTotal,
    Expression<double>? treasuryTotal,
    Expression<double>? profitTotal,
    Expression<double>? profitTransfer,
    Expression<double>? profitReceive,
    Expression<double>? profitFawry,
    Expression<double>? inflow,
    Expression<double>? outflow,
    Expression<double>? net,
    Expression<int>? transferCount,
    Expression<int>? receiveCount,
    Expression<int>? fawryCashCount,
    Expression<int>? fawryCreditCount,
    Expression<int>? expenseCount,
    Expression<int>? claimCollectCount,
    Expression<int>? claimPayCount,
    Expression<int>? pendingCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (dateKey != null) 'date_key': dateKey,
      if (closedAt != null) 'closed_at': closedAt,
      if (drawerBalance != null) 'drawer_balance': drawerBalance,
      if (walletsTotal != null) 'wallets_total': walletsTotal,
      if (treasuryTotal != null) 'treasury_total': treasuryTotal,
      if (profitTotal != null) 'profit_total': profitTotal,
      if (profitTransfer != null) 'profit_transfer': profitTransfer,
      if (profitReceive != null) 'profit_receive': profitReceive,
      if (profitFawry != null) 'profit_fawry': profitFawry,
      if (inflow != null) 'inflow': inflow,
      if (outflow != null) 'outflow': outflow,
      if (net != null) 'net': net,
      if (transferCount != null) 'transfer_count': transferCount,
      if (receiveCount != null) 'receive_count': receiveCount,
      if (fawryCashCount != null) 'fawry_cash_count': fawryCashCount,
      if (fawryCreditCount != null) 'fawry_credit_count': fawryCreditCount,
      if (expenseCount != null) 'expense_count': expenseCount,
      if (claimCollectCount != null) 'claim_collect_count': claimCollectCount,
      if (claimPayCount != null) 'claim_pay_count': claimPayCount,
      if (pendingCount != null) 'pending_count': pendingCount,
    });
  }

  DailyClosesCompanion copyWith({
    Value<int>? id,
    Value<String>? dateKey,
    Value<DateTime>? closedAt,
    Value<double>? drawerBalance,
    Value<double>? walletsTotal,
    Value<double>? treasuryTotal,
    Value<double>? profitTotal,
    Value<double>? profitTransfer,
    Value<double>? profitReceive,
    Value<double>? profitFawry,
    Value<double>? inflow,
    Value<double>? outflow,
    Value<double>? net,
    Value<int>? transferCount,
    Value<int>? receiveCount,
    Value<int>? fawryCashCount,
    Value<int>? fawryCreditCount,
    Value<int>? expenseCount,
    Value<int>? claimCollectCount,
    Value<int>? claimPayCount,
    Value<int>? pendingCount,
  }) {
    return DailyClosesCompanion(
      id: id ?? this.id,
      dateKey: dateKey ?? this.dateKey,
      closedAt: closedAt ?? this.closedAt,
      drawerBalance: drawerBalance ?? this.drawerBalance,
      walletsTotal: walletsTotal ?? this.walletsTotal,
      treasuryTotal: treasuryTotal ?? this.treasuryTotal,
      profitTotal: profitTotal ?? this.profitTotal,
      profitTransfer: profitTransfer ?? this.profitTransfer,
      profitReceive: profitReceive ?? this.profitReceive,
      profitFawry: profitFawry ?? this.profitFawry,
      inflow: inflow ?? this.inflow,
      outflow: outflow ?? this.outflow,
      net: net ?? this.net,
      transferCount: transferCount ?? this.transferCount,
      receiveCount: receiveCount ?? this.receiveCount,
      fawryCashCount: fawryCashCount ?? this.fawryCashCount,
      fawryCreditCount: fawryCreditCount ?? this.fawryCreditCount,
      expenseCount: expenseCount ?? this.expenseCount,
      claimCollectCount: claimCollectCount ?? this.claimCollectCount,
      claimPayCount: claimPayCount ?? this.claimPayCount,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (dateKey.present) {
      map['date_key'] = Variable<String>(dateKey.value);
    }
    if (closedAt.present) {
      map['closed_at'] = Variable<DateTime>(closedAt.value);
    }
    if (drawerBalance.present) {
      map['drawer_balance'] = Variable<double>(drawerBalance.value);
    }
    if (walletsTotal.present) {
      map['wallets_total'] = Variable<double>(walletsTotal.value);
    }
    if (treasuryTotal.present) {
      map['treasury_total'] = Variable<double>(treasuryTotal.value);
    }
    if (profitTotal.present) {
      map['profit_total'] = Variable<double>(profitTotal.value);
    }
    if (profitTransfer.present) {
      map['profit_transfer'] = Variable<double>(profitTransfer.value);
    }
    if (profitReceive.present) {
      map['profit_receive'] = Variable<double>(profitReceive.value);
    }
    if (profitFawry.present) {
      map['profit_fawry'] = Variable<double>(profitFawry.value);
    }
    if (inflow.present) {
      map['inflow'] = Variable<double>(inflow.value);
    }
    if (outflow.present) {
      map['outflow'] = Variable<double>(outflow.value);
    }
    if (net.present) {
      map['net'] = Variable<double>(net.value);
    }
    if (transferCount.present) {
      map['transfer_count'] = Variable<int>(transferCount.value);
    }
    if (receiveCount.present) {
      map['receive_count'] = Variable<int>(receiveCount.value);
    }
    if (fawryCashCount.present) {
      map['fawry_cash_count'] = Variable<int>(fawryCashCount.value);
    }
    if (fawryCreditCount.present) {
      map['fawry_credit_count'] = Variable<int>(fawryCreditCount.value);
    }
    if (expenseCount.present) {
      map['expense_count'] = Variable<int>(expenseCount.value);
    }
    if (claimCollectCount.present) {
      map['claim_collect_count'] = Variable<int>(claimCollectCount.value);
    }
    if (claimPayCount.present) {
      map['claim_pay_count'] = Variable<int>(claimPayCount.value);
    }
    if (pendingCount.present) {
      map['pending_count'] = Variable<int>(pendingCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyClosesCompanion(')
          ..write('id: $id, ')
          ..write('dateKey: $dateKey, ')
          ..write('closedAt: $closedAt, ')
          ..write('drawerBalance: $drawerBalance, ')
          ..write('walletsTotal: $walletsTotal, ')
          ..write('treasuryTotal: $treasuryTotal, ')
          ..write('profitTotal: $profitTotal, ')
          ..write('profitTransfer: $profitTransfer, ')
          ..write('profitReceive: $profitReceive, ')
          ..write('profitFawry: $profitFawry, ')
          ..write('inflow: $inflow, ')
          ..write('outflow: $outflow, ')
          ..write('net: $net, ')
          ..write('transferCount: $transferCount, ')
          ..write('receiveCount: $receiveCount, ')
          ..write('fawryCashCount: $fawryCashCount, ')
          ..write('fawryCreditCount: $fawryCreditCount, ')
          ..write('expenseCount: $expenseCount, ')
          ..write('claimCollectCount: $claimCollectCount, ')
          ..write('claimPayCount: $claimPayCount, ')
          ..write('pendingCount: $pendingCount')
          ..write(')'))
        .toString();
  }
}

class $RecentNumbersTable extends RecentNumbers
    with TableInfo<$RecentNumbersTable, DbRecentNumber> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentNumbersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastUsedMeta = const VerificationMeta(
    'lastUsed',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsed = GeneratedColumn<DateTime>(
    'last_used',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [phone, name, lastUsed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recent_numbers';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbRecentNumber> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    } else if (isInserting) {
      context.missing(_phoneMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('last_used')) {
      context.handle(
        _lastUsedMeta,
        lastUsed.isAcceptableOrUnknown(data['last_used']!, _lastUsedMeta),
      );
    } else if (isInserting) {
      context.missing(_lastUsedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {phone};
  @override
  DbRecentNumber map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbRecentNumber(
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      lastUsed: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used'],
      )!,
    );
  }

  @override
  $RecentNumbersTable createAlias(String alias) {
    return $RecentNumbersTable(attachedDatabase, alias);
  }
}

class DbRecentNumber extends DataClass implements Insertable<DbRecentNumber> {
  final String phone;
  final String? name;
  final DateTime lastUsed;
  const DbRecentNumber({
    required this.phone,
    this.name,
    required this.lastUsed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['phone'] = Variable<String>(phone);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['last_used'] = Variable<DateTime>(lastUsed);
    return map;
  }

  RecentNumbersCompanion toCompanion(bool nullToAbsent) {
    return RecentNumbersCompanion(
      phone: Value(phone),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      lastUsed: Value(lastUsed),
    );
  }

  factory DbRecentNumber.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbRecentNumber(
      phone: serializer.fromJson<String>(json['phone']),
      name: serializer.fromJson<String?>(json['name']),
      lastUsed: serializer.fromJson<DateTime>(json['lastUsed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'phone': serializer.toJson<String>(phone),
      'name': serializer.toJson<String?>(name),
      'lastUsed': serializer.toJson<DateTime>(lastUsed),
    };
  }

  DbRecentNumber copyWith({
    String? phone,
    Value<String?> name = const Value.absent(),
    DateTime? lastUsed,
  }) => DbRecentNumber(
    phone: phone ?? this.phone,
    name: name.present ? name.value : this.name,
    lastUsed: lastUsed ?? this.lastUsed,
  );
  DbRecentNumber copyWithCompanion(RecentNumbersCompanion data) {
    return DbRecentNumber(
      phone: data.phone.present ? data.phone.value : this.phone,
      name: data.name.present ? data.name.value : this.name,
      lastUsed: data.lastUsed.present ? data.lastUsed.value : this.lastUsed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbRecentNumber(')
          ..write('phone: $phone, ')
          ..write('name: $name, ')
          ..write('lastUsed: $lastUsed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(phone, name, lastUsed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbRecentNumber &&
          other.phone == this.phone &&
          other.name == this.name &&
          other.lastUsed == this.lastUsed);
}

class RecentNumbersCompanion extends UpdateCompanion<DbRecentNumber> {
  final Value<String> phone;
  final Value<String?> name;
  final Value<DateTime> lastUsed;
  final Value<int> rowid;
  const RecentNumbersCompanion({
    this.phone = const Value.absent(),
    this.name = const Value.absent(),
    this.lastUsed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecentNumbersCompanion.insert({
    required String phone,
    this.name = const Value.absent(),
    required DateTime lastUsed,
    this.rowid = const Value.absent(),
  }) : phone = Value(phone),
       lastUsed = Value(lastUsed);
  static Insertable<DbRecentNumber> custom({
    Expression<String>? phone,
    Expression<String>? name,
    Expression<DateTime>? lastUsed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (phone != null) 'phone': phone,
      if (name != null) 'name': name,
      if (lastUsed != null) 'last_used': lastUsed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecentNumbersCompanion copyWith({
    Value<String>? phone,
    Value<String?>? name,
    Value<DateTime>? lastUsed,
    Value<int>? rowid,
  }) {
    return RecentNumbersCompanion(
      phone: phone ?? this.phone,
      name: name ?? this.name,
      lastUsed: lastUsed ?? this.lastUsed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (lastUsed.present) {
      map['last_used'] = Variable<DateTime>(lastUsed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentNumbersCompanion(')
          ..write('phone: $phone, ')
          ..write('name: $name, ')
          ..write('lastUsed: $lastUsed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MetaTable extends Meta with TableInfo<$MetaTable, DbMeta> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbMeta> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  DbMeta map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbMeta(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $MetaTable createAlias(String alias) {
    return $MetaTable(attachedDatabase, alias);
  }
}

class DbMeta extends DataClass implements Insertable<DbMeta> {
  final String key;
  final String value;
  const DbMeta({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  MetaCompanion toCompanion(bool nullToAbsent) {
    return MetaCompanion(key: Value(key), value: Value(value));
  }

  factory DbMeta.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbMeta(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  DbMeta copyWith({String? key, String? value}) =>
      DbMeta(key: key ?? this.key, value: value ?? this.value);
  DbMeta copyWithCompanion(MetaCompanion data) {
    return DbMeta(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbMeta(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbMeta && other.key == this.key && other.value == this.value);
}

class MetaCompanion extends UpdateCompanion<DbMeta> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const MetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<DbMeta> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return MetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, DbOutbox> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<DateTime> sentAt = GeneratedColumn<DateTime>(
    'sent_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entity,
    entityId,
    action,
    payload,
    createdAt,
    sentAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbOutbox> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DbOutbox map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbOutbox(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sent_at'],
      ),
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class DbOutbox extends DataClass implements Insertable<DbOutbox> {
  final int id;
  final String entity;
  final String entityId;
  final String action;
  final String? payload;
  final DateTime createdAt;
  final DateTime? sentAt;
  const DbOutbox({
    required this.id,
    required this.entity,
    required this.entityId,
    required this.action,
    this.payload,
    required this.createdAt,
    this.sentAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entity'] = Variable<String>(entity);
    map['entity_id'] = Variable<String>(entityId);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<String>(payload);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || sentAt != null) {
      map['sent_at'] = Variable<DateTime>(sentAt);
    }
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      id: Value(id),
      entity: Value(entity),
      entityId: Value(entityId),
      action: Value(action),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      createdAt: Value(createdAt),
      sentAt: sentAt == null && nullToAbsent
          ? const Value.absent()
          : Value(sentAt),
    );
  }

  factory DbOutbox.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbOutbox(
      id: serializer.fromJson<int>(json['id']),
      entity: serializer.fromJson<String>(json['entity']),
      entityId: serializer.fromJson<String>(json['entityId']),
      action: serializer.fromJson<String>(json['action']),
      payload: serializer.fromJson<String?>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sentAt: serializer.fromJson<DateTime?>(json['sentAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entity': serializer.toJson<String>(entity),
      'entityId': serializer.toJson<String>(entityId),
      'action': serializer.toJson<String>(action),
      'payload': serializer.toJson<String?>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sentAt': serializer.toJson<DateTime?>(sentAt),
    };
  }

  DbOutbox copyWith({
    int? id,
    String? entity,
    String? entityId,
    String? action,
    Value<String?> payload = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> sentAt = const Value.absent(),
  }) => DbOutbox(
    id: id ?? this.id,
    entity: entity ?? this.entity,
    entityId: entityId ?? this.entityId,
    action: action ?? this.action,
    payload: payload.present ? payload.value : this.payload,
    createdAt: createdAt ?? this.createdAt,
    sentAt: sentAt.present ? sentAt.value : this.sentAt,
  );
  DbOutbox copyWithCompanion(SyncOutboxCompanion data) {
    return DbOutbox(
      id: data.id.present ? data.id.value : this.id,
      entity: data.entity.present ? data.entity.value : this.entity,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      action: data.action.present ? data.action.value : this.action,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbOutbox(')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('sentAt: $sentAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, entity, entityId, action, payload, createdAt, sentAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbOutbox &&
          other.id == this.id &&
          other.entity == this.entity &&
          other.entityId == this.entityId &&
          other.action == this.action &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.sentAt == this.sentAt);
}

class SyncOutboxCompanion extends UpdateCompanion<DbOutbox> {
  final Value<int> id;
  final Value<String> entity;
  final Value<String> entityId;
  final Value<String> action;
  final Value<String?> payload;
  final Value<DateTime> createdAt;
  final Value<DateTime?> sentAt;
  const SyncOutboxCompanion({
    this.id = const Value.absent(),
    this.entity = const Value.absent(),
    this.entityId = const Value.absent(),
    this.action = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sentAt = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    this.id = const Value.absent(),
    required String entity,
    required String entityId,
    required String action,
    this.payload = const Value.absent(),
    required DateTime createdAt,
    this.sentAt = const Value.absent(),
  }) : entity = Value(entity),
       entityId = Value(entityId),
       action = Value(action),
       createdAt = Value(createdAt);
  static Insertable<DbOutbox> custom({
    Expression<int>? id,
    Expression<String>? entity,
    Expression<String>? entityId,
    Expression<String>? action,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? sentAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entity != null) 'entity': entity,
      if (entityId != null) 'entity_id': entityId,
      if (action != null) 'action': action,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (sentAt != null) 'sent_at': sentAt,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<int>? id,
    Value<String>? entity,
    Value<String>? entityId,
    Value<String>? action,
    Value<String?>? payload,
    Value<DateTime>? createdAt,
    Value<DateTime?>? sentAt,
  }) {
    return SyncOutboxCompanion(
      id: id ?? this.id,
      entity: entity ?? this.entity,
      entityId: entityId ?? this.entityId,
      action: action ?? this.action,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      sentAt: sentAt ?? this.sentAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<DateTime>(sentAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('sentAt: $sentAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $WalletsTable wallets = $WalletsTable(this);
  late final $TxnsTable txns = $TxnsTable(this);
  late final $ClaimsTable claims = $ClaimsTable(this);
  late final $DailyClosesTable dailyCloses = $DailyClosesTable(this);
  late final $RecentNumbersTable recentNumbers = $RecentNumbersTable(this);
  late final $MetaTable meta = $MetaTable(this);
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    wallets,
    txns,
    claims,
    dailyCloses,
    recentNumbers,
    meta,
    syncOutbox,
  ];
}

typedef $$WalletsTableCreateCompanionBuilder =
    WalletsCompanion Function({
      Value<int> id,
      required String name,
      Value<bool> allowNegative,
      Value<String> phone,
      required double dailyLimit,
      required double monthlyLimit,
      required double lowBalanceThreshold,
    });
typedef $$WalletsTableUpdateCompanionBuilder =
    WalletsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<bool> allowNegative,
      Value<String> phone,
      Value<double> dailyLimit,
      Value<double> monthlyLimit,
      Value<double> lowBalanceThreshold,
    });

class $$WalletsTableFilterComposer
    extends Composer<_$AppDatabase, $WalletsTable> {
  $$WalletsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allowNegative => $composableBuilder(
    column: $table.allowNegative,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get dailyLimit => $composableBuilder(
    column: $table.dailyLimit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get monthlyLimit => $composableBuilder(
    column: $table.monthlyLimit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lowBalanceThreshold => $composableBuilder(
    column: $table.lowBalanceThreshold,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WalletsTableOrderingComposer
    extends Composer<_$AppDatabase, $WalletsTable> {
  $$WalletsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allowNegative => $composableBuilder(
    column: $table.allowNegative,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get dailyLimit => $composableBuilder(
    column: $table.dailyLimit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get monthlyLimit => $composableBuilder(
    column: $table.monthlyLimit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lowBalanceThreshold => $composableBuilder(
    column: $table.lowBalanceThreshold,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WalletsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WalletsTable> {
  $$WalletsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get allowNegative => $composableBuilder(
    column: $table.allowNegative,
    builder: (column) => column,
  );

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<double> get dailyLimit => $composableBuilder(
    column: $table.dailyLimit,
    builder: (column) => column,
  );

  GeneratedColumn<double> get monthlyLimit => $composableBuilder(
    column: $table.monthlyLimit,
    builder: (column) => column,
  );

  GeneratedColumn<double> get lowBalanceThreshold => $composableBuilder(
    column: $table.lowBalanceThreshold,
    builder: (column) => column,
  );
}

class $$WalletsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WalletsTable,
          DbWallet,
          $$WalletsTableFilterComposer,
          $$WalletsTableOrderingComposer,
          $$WalletsTableAnnotationComposer,
          $$WalletsTableCreateCompanionBuilder,
          $$WalletsTableUpdateCompanionBuilder,
          (DbWallet, BaseReferences<_$AppDatabase, $WalletsTable, DbWallet>),
          DbWallet,
          PrefetchHooks Function()
        > {
  $$WalletsTableTableManager(_$AppDatabase db, $WalletsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WalletsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WalletsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WalletsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> allowNegative = const Value.absent(),
                Value<String> phone = const Value.absent(),
                Value<double> dailyLimit = const Value.absent(),
                Value<double> monthlyLimit = const Value.absent(),
                Value<double> lowBalanceThreshold = const Value.absent(),
              }) => WalletsCompanion(
                id: id,
                name: name,
                allowNegative: allowNegative,
                phone: phone,
                dailyLimit: dailyLimit,
                monthlyLimit: monthlyLimit,
                lowBalanceThreshold: lowBalanceThreshold,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<bool> allowNegative = const Value.absent(),
                Value<String> phone = const Value.absent(),
                required double dailyLimit,
                required double monthlyLimit,
                required double lowBalanceThreshold,
              }) => WalletsCompanion.insert(
                id: id,
                name: name,
                allowNegative: allowNegative,
                phone: phone,
                dailyLimit: dailyLimit,
                monthlyLimit: monthlyLimit,
                lowBalanceThreshold: lowBalanceThreshold,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WalletsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WalletsTable,
      DbWallet,
      $$WalletsTableFilterComposer,
      $$WalletsTableOrderingComposer,
      $$WalletsTableAnnotationComposer,
      $$WalletsTableCreateCompanionBuilder,
      $$WalletsTableUpdateCompanionBuilder,
      (DbWallet, BaseReferences<_$AppDatabase, $WalletsTable, DbWallet>),
      DbWallet,
      PrefetchHooks Function()
    >;
typedef $$TxnsTableCreateCompanionBuilder =
    TxnsCompanion Function({
      Value<int> id,
      required String kind,
      required String status,
      required DateTime entryDate,
      Value<int?> walletFromId,
      Value<int?> walletToId,
      required double amount,
      required double clientFee,
      required double networkFee,
      required String mode,
      Value<String?> note,
      Value<String?> serviceName,
      Value<String?> reference,
      Value<String?> party,
      required String createdBy,
      required String createdRole,
      required DateTime createdAt,
    });
typedef $$TxnsTableUpdateCompanionBuilder =
    TxnsCompanion Function({
      Value<int> id,
      Value<String> kind,
      Value<String> status,
      Value<DateTime> entryDate,
      Value<int?> walletFromId,
      Value<int?> walletToId,
      Value<double> amount,
      Value<double> clientFee,
      Value<double> networkFee,
      Value<String> mode,
      Value<String?> note,
      Value<String?> serviceName,
      Value<String?> reference,
      Value<String?> party,
      Value<String> createdBy,
      Value<String> createdRole,
      Value<DateTime> createdAt,
    });

class $$TxnsTableFilterComposer extends Composer<_$AppDatabase, $TxnsTable> {
  $$TxnsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get entryDate => $composableBuilder(
    column: $table.entryDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get walletFromId => $composableBuilder(
    column: $table.walletFromId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get walletToId => $composableBuilder(
    column: $table.walletToId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get clientFee => $composableBuilder(
    column: $table.clientFee,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get networkFee => $composableBuilder(
    column: $table.networkFee,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serviceName => $composableBuilder(
    column: $table.serviceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get party => $composableBuilder(
    column: $table.party,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdRole => $composableBuilder(
    column: $table.createdRole,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TxnsTableOrderingComposer extends Composer<_$AppDatabase, $TxnsTable> {
  $$TxnsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get entryDate => $composableBuilder(
    column: $table.entryDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get walletFromId => $composableBuilder(
    column: $table.walletFromId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get walletToId => $composableBuilder(
    column: $table.walletToId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get clientFee => $composableBuilder(
    column: $table.clientFee,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get networkFee => $composableBuilder(
    column: $table.networkFee,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serviceName => $composableBuilder(
    column: $table.serviceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get party => $composableBuilder(
    column: $table.party,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdRole => $composableBuilder(
    column: $table.createdRole,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TxnsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TxnsTable> {
  $$TxnsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get entryDate =>
      $composableBuilder(column: $table.entryDate, builder: (column) => column);

  GeneratedColumn<int> get walletFromId => $composableBuilder(
    column: $table.walletFromId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get walletToId => $composableBuilder(
    column: $table.walletToId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<double> get clientFee =>
      $composableBuilder(column: $table.clientFee, builder: (column) => column);

  GeneratedColumn<double> get networkFee => $composableBuilder(
    column: $table.networkFee,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get serviceName => $composableBuilder(
    column: $table.serviceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reference =>
      $composableBuilder(column: $table.reference, builder: (column) => column);

  GeneratedColumn<String> get party =>
      $composableBuilder(column: $table.party, builder: (column) => column);

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<String> get createdRole => $composableBuilder(
    column: $table.createdRole,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TxnsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TxnsTable,
          DbTxn,
          $$TxnsTableFilterComposer,
          $$TxnsTableOrderingComposer,
          $$TxnsTableAnnotationComposer,
          $$TxnsTableCreateCompanionBuilder,
          $$TxnsTableUpdateCompanionBuilder,
          (DbTxn, BaseReferences<_$AppDatabase, $TxnsTable, DbTxn>),
          DbTxn,
          PrefetchHooks Function()
        > {
  $$TxnsTableTableManager(_$AppDatabase db, $TxnsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TxnsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TxnsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TxnsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> entryDate = const Value.absent(),
                Value<int?> walletFromId = const Value.absent(),
                Value<int?> walletToId = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<double> clientFee = const Value.absent(),
                Value<double> networkFee = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> serviceName = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<String?> party = const Value.absent(),
                Value<String> createdBy = const Value.absent(),
                Value<String> createdRole = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TxnsCompanion(
                id: id,
                kind: kind,
                status: status,
                entryDate: entryDate,
                walletFromId: walletFromId,
                walletToId: walletToId,
                amount: amount,
                clientFee: clientFee,
                networkFee: networkFee,
                mode: mode,
                note: note,
                serviceName: serviceName,
                reference: reference,
                party: party,
                createdBy: createdBy,
                createdRole: createdRole,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String kind,
                required String status,
                required DateTime entryDate,
                Value<int?> walletFromId = const Value.absent(),
                Value<int?> walletToId = const Value.absent(),
                required double amount,
                required double clientFee,
                required double networkFee,
                required String mode,
                Value<String?> note = const Value.absent(),
                Value<String?> serviceName = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<String?> party = const Value.absent(),
                required String createdBy,
                required String createdRole,
                required DateTime createdAt,
              }) => TxnsCompanion.insert(
                id: id,
                kind: kind,
                status: status,
                entryDate: entryDate,
                walletFromId: walletFromId,
                walletToId: walletToId,
                amount: amount,
                clientFee: clientFee,
                networkFee: networkFee,
                mode: mode,
                note: note,
                serviceName: serviceName,
                reference: reference,
                party: party,
                createdBy: createdBy,
                createdRole: createdRole,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TxnsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TxnsTable,
      DbTxn,
      $$TxnsTableFilterComposer,
      $$TxnsTableOrderingComposer,
      $$TxnsTableAnnotationComposer,
      $$TxnsTableCreateCompanionBuilder,
      $$TxnsTableUpdateCompanionBuilder,
      (DbTxn, BaseReferences<_$AppDatabase, $TxnsTable, DbTxn>),
      DbTxn,
      PrefetchHooks Function()
    >;
typedef $$ClaimsTableCreateCompanionBuilder =
    ClaimsCompanion Function({
      Value<int> id,
      required String type,
      required String party,
      required double amount,
      Value<String?> note,
      required DateTime entryDate,
      required String status,
      Value<int?> settledTxnId,
      Value<DateTime?> settledDate,
      Value<int?> sourceTxnId,
    });
typedef $$ClaimsTableUpdateCompanionBuilder =
    ClaimsCompanion Function({
      Value<int> id,
      Value<String> type,
      Value<String> party,
      Value<double> amount,
      Value<String?> note,
      Value<DateTime> entryDate,
      Value<String> status,
      Value<int?> settledTxnId,
      Value<DateTime?> settledDate,
      Value<int?> sourceTxnId,
    });

class $$ClaimsTableFilterComposer
    extends Composer<_$AppDatabase, $ClaimsTable> {
  $$ClaimsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get party => $composableBuilder(
    column: $table.party,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get entryDate => $composableBuilder(
    column: $table.entryDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get settledTxnId => $composableBuilder(
    column: $table.settledTxnId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get settledDate => $composableBuilder(
    column: $table.settledDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceTxnId => $composableBuilder(
    column: $table.sourceTxnId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ClaimsTableOrderingComposer
    extends Composer<_$AppDatabase, $ClaimsTable> {
  $$ClaimsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get party => $composableBuilder(
    column: $table.party,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get entryDate => $composableBuilder(
    column: $table.entryDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get settledTxnId => $composableBuilder(
    column: $table.settledTxnId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get settledDate => $composableBuilder(
    column: $table.settledDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceTxnId => $composableBuilder(
    column: $table.sourceTxnId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ClaimsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClaimsTable> {
  $$ClaimsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get party =>
      $composableBuilder(column: $table.party, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get entryDate =>
      $composableBuilder(column: $table.entryDate, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get settledTxnId => $composableBuilder(
    column: $table.settledTxnId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get settledDate => $composableBuilder(
    column: $table.settledDate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sourceTxnId => $composableBuilder(
    column: $table.sourceTxnId,
    builder: (column) => column,
  );
}

class $$ClaimsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ClaimsTable,
          DbClaim,
          $$ClaimsTableFilterComposer,
          $$ClaimsTableOrderingComposer,
          $$ClaimsTableAnnotationComposer,
          $$ClaimsTableCreateCompanionBuilder,
          $$ClaimsTableUpdateCompanionBuilder,
          (DbClaim, BaseReferences<_$AppDatabase, $ClaimsTable, DbClaim>),
          DbClaim,
          PrefetchHooks Function()
        > {
  $$ClaimsTableTableManager(_$AppDatabase db, $ClaimsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClaimsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClaimsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClaimsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> party = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> entryDate = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> settledTxnId = const Value.absent(),
                Value<DateTime?> settledDate = const Value.absent(),
                Value<int?> sourceTxnId = const Value.absent(),
              }) => ClaimsCompanion(
                id: id,
                type: type,
                party: party,
                amount: amount,
                note: note,
                entryDate: entryDate,
                status: status,
                settledTxnId: settledTxnId,
                settledDate: settledDate,
                sourceTxnId: sourceTxnId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String type,
                required String party,
                required double amount,
                Value<String?> note = const Value.absent(),
                required DateTime entryDate,
                required String status,
                Value<int?> settledTxnId = const Value.absent(),
                Value<DateTime?> settledDate = const Value.absent(),
                Value<int?> sourceTxnId = const Value.absent(),
              }) => ClaimsCompanion.insert(
                id: id,
                type: type,
                party: party,
                amount: amount,
                note: note,
                entryDate: entryDate,
                status: status,
                settledTxnId: settledTxnId,
                settledDate: settledDate,
                sourceTxnId: sourceTxnId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ClaimsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ClaimsTable,
      DbClaim,
      $$ClaimsTableFilterComposer,
      $$ClaimsTableOrderingComposer,
      $$ClaimsTableAnnotationComposer,
      $$ClaimsTableCreateCompanionBuilder,
      $$ClaimsTableUpdateCompanionBuilder,
      (DbClaim, BaseReferences<_$AppDatabase, $ClaimsTable, DbClaim>),
      DbClaim,
      PrefetchHooks Function()
    >;
typedef $$DailyClosesTableCreateCompanionBuilder =
    DailyClosesCompanion Function({
      Value<int> id,
      required String dateKey,
      required DateTime closedAt,
      required double drawerBalance,
      required double walletsTotal,
      required double treasuryTotal,
      required double profitTotal,
      required double profitTransfer,
      required double profitReceive,
      required double profitFawry,
      required double inflow,
      required double outflow,
      required double net,
      required int transferCount,
      required int receiveCount,
      required int fawryCashCount,
      required int fawryCreditCount,
      required int expenseCount,
      required int claimCollectCount,
      required int claimPayCount,
      required int pendingCount,
    });
typedef $$DailyClosesTableUpdateCompanionBuilder =
    DailyClosesCompanion Function({
      Value<int> id,
      Value<String> dateKey,
      Value<DateTime> closedAt,
      Value<double> drawerBalance,
      Value<double> walletsTotal,
      Value<double> treasuryTotal,
      Value<double> profitTotal,
      Value<double> profitTransfer,
      Value<double> profitReceive,
      Value<double> profitFawry,
      Value<double> inflow,
      Value<double> outflow,
      Value<double> net,
      Value<int> transferCount,
      Value<int> receiveCount,
      Value<int> fawryCashCount,
      Value<int> fawryCreditCount,
      Value<int> expenseCount,
      Value<int> claimCollectCount,
      Value<int> claimPayCount,
      Value<int> pendingCount,
    });

class $$DailyClosesTableFilterComposer
    extends Composer<_$AppDatabase, $DailyClosesTable> {
  $$DailyClosesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dateKey => $composableBuilder(
    column: $table.dateKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get drawerBalance => $composableBuilder(
    column: $table.drawerBalance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get walletsTotal => $composableBuilder(
    column: $table.walletsTotal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get treasuryTotal => $composableBuilder(
    column: $table.treasuryTotal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get profitTotal => $composableBuilder(
    column: $table.profitTotal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get profitTransfer => $composableBuilder(
    column: $table.profitTransfer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get profitReceive => $composableBuilder(
    column: $table.profitReceive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get profitFawry => $composableBuilder(
    column: $table.profitFawry,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get inflow => $composableBuilder(
    column: $table.inflow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get outflow => $composableBuilder(
    column: $table.outflow,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get net => $composableBuilder(
    column: $table.net,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get transferCount => $composableBuilder(
    column: $table.transferCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receiveCount => $composableBuilder(
    column: $table.receiveCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fawryCashCount => $composableBuilder(
    column: $table.fawryCashCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fawryCreditCount => $composableBuilder(
    column: $table.fawryCreditCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expenseCount => $composableBuilder(
    column: $table.expenseCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get claimCollectCount => $composableBuilder(
    column: $table.claimCollectCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get claimPayCount => $composableBuilder(
    column: $table.claimPayCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pendingCount => $composableBuilder(
    column: $table.pendingCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyClosesTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyClosesTable> {
  $$DailyClosesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dateKey => $composableBuilder(
    column: $table.dateKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get drawerBalance => $composableBuilder(
    column: $table.drawerBalance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get walletsTotal => $composableBuilder(
    column: $table.walletsTotal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get treasuryTotal => $composableBuilder(
    column: $table.treasuryTotal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get profitTotal => $composableBuilder(
    column: $table.profitTotal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get profitTransfer => $composableBuilder(
    column: $table.profitTransfer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get profitReceive => $composableBuilder(
    column: $table.profitReceive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get profitFawry => $composableBuilder(
    column: $table.profitFawry,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get inflow => $composableBuilder(
    column: $table.inflow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get outflow => $composableBuilder(
    column: $table.outflow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get net => $composableBuilder(
    column: $table.net,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get transferCount => $composableBuilder(
    column: $table.transferCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receiveCount => $composableBuilder(
    column: $table.receiveCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fawryCashCount => $composableBuilder(
    column: $table.fawryCashCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fawryCreditCount => $composableBuilder(
    column: $table.fawryCreditCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expenseCount => $composableBuilder(
    column: $table.expenseCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get claimCollectCount => $composableBuilder(
    column: $table.claimCollectCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get claimPayCount => $composableBuilder(
    column: $table.claimPayCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pendingCount => $composableBuilder(
    column: $table.pendingCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyClosesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyClosesTable> {
  $$DailyClosesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get dateKey =>
      $composableBuilder(column: $table.dateKey, builder: (column) => column);

  GeneratedColumn<DateTime> get closedAt =>
      $composableBuilder(column: $table.closedAt, builder: (column) => column);

  GeneratedColumn<double> get drawerBalance => $composableBuilder(
    column: $table.drawerBalance,
    builder: (column) => column,
  );

  GeneratedColumn<double> get walletsTotal => $composableBuilder(
    column: $table.walletsTotal,
    builder: (column) => column,
  );

  GeneratedColumn<double> get treasuryTotal => $composableBuilder(
    column: $table.treasuryTotal,
    builder: (column) => column,
  );

  GeneratedColumn<double> get profitTotal => $composableBuilder(
    column: $table.profitTotal,
    builder: (column) => column,
  );

  GeneratedColumn<double> get profitTransfer => $composableBuilder(
    column: $table.profitTransfer,
    builder: (column) => column,
  );

  GeneratedColumn<double> get profitReceive => $composableBuilder(
    column: $table.profitReceive,
    builder: (column) => column,
  );

  GeneratedColumn<double> get profitFawry => $composableBuilder(
    column: $table.profitFawry,
    builder: (column) => column,
  );

  GeneratedColumn<double> get inflow =>
      $composableBuilder(column: $table.inflow, builder: (column) => column);

  GeneratedColumn<double> get outflow =>
      $composableBuilder(column: $table.outflow, builder: (column) => column);

  GeneratedColumn<double> get net =>
      $composableBuilder(column: $table.net, builder: (column) => column);

  GeneratedColumn<int> get transferCount => $composableBuilder(
    column: $table.transferCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get receiveCount => $composableBuilder(
    column: $table.receiveCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fawryCashCount => $composableBuilder(
    column: $table.fawryCashCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fawryCreditCount => $composableBuilder(
    column: $table.fawryCreditCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get expenseCount => $composableBuilder(
    column: $table.expenseCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get claimCollectCount => $composableBuilder(
    column: $table.claimCollectCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get claimPayCount => $composableBuilder(
    column: $table.claimPayCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pendingCount => $composableBuilder(
    column: $table.pendingCount,
    builder: (column) => column,
  );
}

class $$DailyClosesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyClosesTable,
          DbDailyClose,
          $$DailyClosesTableFilterComposer,
          $$DailyClosesTableOrderingComposer,
          $$DailyClosesTableAnnotationComposer,
          $$DailyClosesTableCreateCompanionBuilder,
          $$DailyClosesTableUpdateCompanionBuilder,
          (
            DbDailyClose,
            BaseReferences<_$AppDatabase, $DailyClosesTable, DbDailyClose>,
          ),
          DbDailyClose,
          PrefetchHooks Function()
        > {
  $$DailyClosesTableTableManager(_$AppDatabase db, $DailyClosesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyClosesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyClosesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyClosesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> dateKey = const Value.absent(),
                Value<DateTime> closedAt = const Value.absent(),
                Value<double> drawerBalance = const Value.absent(),
                Value<double> walletsTotal = const Value.absent(),
                Value<double> treasuryTotal = const Value.absent(),
                Value<double> profitTotal = const Value.absent(),
                Value<double> profitTransfer = const Value.absent(),
                Value<double> profitReceive = const Value.absent(),
                Value<double> profitFawry = const Value.absent(),
                Value<double> inflow = const Value.absent(),
                Value<double> outflow = const Value.absent(),
                Value<double> net = const Value.absent(),
                Value<int> transferCount = const Value.absent(),
                Value<int> receiveCount = const Value.absent(),
                Value<int> fawryCashCount = const Value.absent(),
                Value<int> fawryCreditCount = const Value.absent(),
                Value<int> expenseCount = const Value.absent(),
                Value<int> claimCollectCount = const Value.absent(),
                Value<int> claimPayCount = const Value.absent(),
                Value<int> pendingCount = const Value.absent(),
              }) => DailyClosesCompanion(
                id: id,
                dateKey: dateKey,
                closedAt: closedAt,
                drawerBalance: drawerBalance,
                walletsTotal: walletsTotal,
                treasuryTotal: treasuryTotal,
                profitTotal: profitTotal,
                profitTransfer: profitTransfer,
                profitReceive: profitReceive,
                profitFawry: profitFawry,
                inflow: inflow,
                outflow: outflow,
                net: net,
                transferCount: transferCount,
                receiveCount: receiveCount,
                fawryCashCount: fawryCashCount,
                fawryCreditCount: fawryCreditCount,
                expenseCount: expenseCount,
                claimCollectCount: claimCollectCount,
                claimPayCount: claimPayCount,
                pendingCount: pendingCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String dateKey,
                required DateTime closedAt,
                required double drawerBalance,
                required double walletsTotal,
                required double treasuryTotal,
                required double profitTotal,
                required double profitTransfer,
                required double profitReceive,
                required double profitFawry,
                required double inflow,
                required double outflow,
                required double net,
                required int transferCount,
                required int receiveCount,
                required int fawryCashCount,
                required int fawryCreditCount,
                required int expenseCount,
                required int claimCollectCount,
                required int claimPayCount,
                required int pendingCount,
              }) => DailyClosesCompanion.insert(
                id: id,
                dateKey: dateKey,
                closedAt: closedAt,
                drawerBalance: drawerBalance,
                walletsTotal: walletsTotal,
                treasuryTotal: treasuryTotal,
                profitTotal: profitTotal,
                profitTransfer: profitTransfer,
                profitReceive: profitReceive,
                profitFawry: profitFawry,
                inflow: inflow,
                outflow: outflow,
                net: net,
                transferCount: transferCount,
                receiveCount: receiveCount,
                fawryCashCount: fawryCashCount,
                fawryCreditCount: fawryCreditCount,
                expenseCount: expenseCount,
                claimCollectCount: claimCollectCount,
                claimPayCount: claimPayCount,
                pendingCount: pendingCount,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyClosesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyClosesTable,
      DbDailyClose,
      $$DailyClosesTableFilterComposer,
      $$DailyClosesTableOrderingComposer,
      $$DailyClosesTableAnnotationComposer,
      $$DailyClosesTableCreateCompanionBuilder,
      $$DailyClosesTableUpdateCompanionBuilder,
      (
        DbDailyClose,
        BaseReferences<_$AppDatabase, $DailyClosesTable, DbDailyClose>,
      ),
      DbDailyClose,
      PrefetchHooks Function()
    >;
typedef $$RecentNumbersTableCreateCompanionBuilder =
    RecentNumbersCompanion Function({
      required String phone,
      Value<String?> name,
      required DateTime lastUsed,
      Value<int> rowid,
    });
typedef $$RecentNumbersTableUpdateCompanionBuilder =
    RecentNumbersCompanion Function({
      Value<String> phone,
      Value<String?> name,
      Value<DateTime> lastUsed,
      Value<int> rowid,
    });

class $$RecentNumbersTableFilterComposer
    extends Composer<_$AppDatabase, $RecentNumbersTable> {
  $$RecentNumbersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsed => $composableBuilder(
    column: $table.lastUsed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecentNumbersTableOrderingComposer
    extends Composer<_$AppDatabase, $RecentNumbersTable> {
  $$RecentNumbersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsed => $composableBuilder(
    column: $table.lastUsed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecentNumbersTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecentNumbersTable> {
  $$RecentNumbersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsed =>
      $composableBuilder(column: $table.lastUsed, builder: (column) => column);
}

class $$RecentNumbersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecentNumbersTable,
          DbRecentNumber,
          $$RecentNumbersTableFilterComposer,
          $$RecentNumbersTableOrderingComposer,
          $$RecentNumbersTableAnnotationComposer,
          $$RecentNumbersTableCreateCompanionBuilder,
          $$RecentNumbersTableUpdateCompanionBuilder,
          (
            DbRecentNumber,
            BaseReferences<_$AppDatabase, $RecentNumbersTable, DbRecentNumber>,
          ),
          DbRecentNumber,
          PrefetchHooks Function()
        > {
  $$RecentNumbersTableTableManager(_$AppDatabase db, $RecentNumbersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecentNumbersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecentNumbersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecentNumbersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> phone = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<DateTime> lastUsed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RecentNumbersCompanion(
                phone: phone,
                name: name,
                lastUsed: lastUsed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String phone,
                Value<String?> name = const Value.absent(),
                required DateTime lastUsed,
                Value<int> rowid = const Value.absent(),
              }) => RecentNumbersCompanion.insert(
                phone: phone,
                name: name,
                lastUsed: lastUsed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecentNumbersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecentNumbersTable,
      DbRecentNumber,
      $$RecentNumbersTableFilterComposer,
      $$RecentNumbersTableOrderingComposer,
      $$RecentNumbersTableAnnotationComposer,
      $$RecentNumbersTableCreateCompanionBuilder,
      $$RecentNumbersTableUpdateCompanionBuilder,
      (
        DbRecentNumber,
        BaseReferences<_$AppDatabase, $RecentNumbersTable, DbRecentNumber>,
      ),
      DbRecentNumber,
      PrefetchHooks Function()
    >;
typedef $$MetaTableCreateCompanionBuilder =
    MetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$MetaTableUpdateCompanionBuilder =
    MetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$MetaTableFilterComposer extends Composer<_$AppDatabase, $MetaTable> {
  $$MetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MetaTableOrderingComposer extends Composer<_$AppDatabase, $MetaTable> {
  $$MetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $MetaTable> {
  $$MetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$MetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MetaTable,
          DbMeta,
          $$MetaTableFilterComposer,
          $$MetaTableOrderingComposer,
          $$MetaTableAnnotationComposer,
          $$MetaTableCreateCompanionBuilder,
          $$MetaTableUpdateCompanionBuilder,
          (DbMeta, BaseReferences<_$AppDatabase, $MetaTable, DbMeta>),
          DbMeta,
          PrefetchHooks Function()
        > {
  $$MetaTableTableManager(_$AppDatabase db, $MetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => MetaCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MetaTable,
      DbMeta,
      $$MetaTableFilterComposer,
      $$MetaTableOrderingComposer,
      $$MetaTableAnnotationComposer,
      $$MetaTableCreateCompanionBuilder,
      $$MetaTableUpdateCompanionBuilder,
      (DbMeta, BaseReferences<_$AppDatabase, $MetaTable, DbMeta>),
      DbMeta,
      PrefetchHooks Function()
    >;
typedef $$SyncOutboxTableCreateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<int> id,
      required String entity,
      required String entityId,
      required String action,
      Value<String?> payload,
      required DateTime createdAt,
      Value<DateTime?> sentAt,
    });
typedef $$SyncOutboxTableUpdateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<int> id,
      Value<String> entity,
      Value<String> entityId,
      Value<String> action,
      Value<String?> payload,
      Value<DateTime> createdAt,
      Value<DateTime?> sentAt,
    });

class $$SyncOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);
}

class $$SyncOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOutboxTable,
          DbOutbox,
          $$SyncOutboxTableFilterComposer,
          $$SyncOutboxTableOrderingComposer,
          $$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (DbOutbox, BaseReferences<_$AppDatabase, $SyncOutboxTable, DbOutbox>),
          DbOutbox,
          PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(_$AppDatabase db, $SyncOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> sentAt = const Value.absent(),
              }) => SyncOutboxCompanion(
                id: id,
                entity: entity,
                entityId: entityId,
                action: action,
                payload: payload,
                createdAt: createdAt,
                sentAt: sentAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String entity,
                required String entityId,
                required String action,
                Value<String?> payload = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> sentAt = const Value.absent(),
              }) => SyncOutboxCompanion.insert(
                id: id,
                entity: entity,
                entityId: entityId,
                action: action,
                payload: payload,
                createdAt: createdAt,
                sentAt: sentAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOutboxTable,
      DbOutbox,
      $$SyncOutboxTableFilterComposer,
      $$SyncOutboxTableOrderingComposer,
      $$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (DbOutbox, BaseReferences<_$AppDatabase, $SyncOutboxTable, DbOutbox>),
      DbOutbox,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$WalletsTableTableManager get wallets =>
      $$WalletsTableTableManager(_db, _db.wallets);
  $$TxnsTableTableManager get txns => $$TxnsTableTableManager(_db, _db.txns);
  $$ClaimsTableTableManager get claims =>
      $$ClaimsTableTableManager(_db, _db.claims);
  $$DailyClosesTableTableManager get dailyCloses =>
      $$DailyClosesTableTableManager(_db, _db.dailyCloses);
  $$RecentNumbersTableTableManager get recentNumbers =>
      $$RecentNumbersTableTableManager(_db, _db.recentNumbers);
  $$MetaTableTableManager get meta => $$MetaTableTableManager(_db, _db.meta);
  $$SyncOutboxTableTableManager get syncOutbox =>
      $$SyncOutboxTableTableManager(_db, _db.syncOutbox);
}
