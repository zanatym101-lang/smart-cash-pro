const Map<String, List<String>> financialSenderAliasesByProvider = {
  'Vodafone Cash': <String>[
    'vf-cash',
    'vfcash',
    'vf cash',
    'vodafone cash',
    'vodafone',
    'vodafone365',
    'فودافون كاش',
    'فودافون',
  ],
  'Etisalat Cash': <String>[
    'etisalat cash',
    'etisalatcash',
    'etisalat',
    'e& money',
    'e&money',
    'e&',
    'اتصالات كاش',
    'اتصالات',
    'اي اند موني',
    'إي آند موني',
    'إي آند',
  ],
  'Orange Money': <String>[
    'orange money',
    'orangemoney',
    'orange cash',
    'orangecash',
    'orange',
    'اورنج موني',
    'أورنج موني',
    'اورنج كاش',
    'أورنج كاش',
    'اورنج',
    'أورنج',
  ],
  'WePay': <String>[
    'wepay',
    'we pay',
    'we cash',
    'we',
    'وي باي',
    'وى باي',
    'وي كاش',
    'المصرية للاتصالات',
  ],
  'InstaPay': <String>[
    'instapay',
    'insta pay',
    'ipn',
    'انستا باي',
    'انستاباي',
    'المدفوعات اللحظية',
  ],
  'Fawry': <String>[
    'fawry',
    'fawrypay',
    'fawry cash',
    'فوري',
    'فورى',
    'فوري باي',
    'فوري كاش',
  ],
  'Bank': <String>[
    'nbe',
    'ahli bank',
    'الأهلي',
    'البنك الأهلي',
    'banque misr',
    'bm',
    'بنك مصر',
    'cib',
    'cib eg',
    'qnb',
    'alexbank',
    'بنك الإسكندرية',
    'banque du caire',
    'بنك القاهرة',
    'bdc',
  ],
};

String _normalizeFinancialSender(String sender) {
  return sender.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

List<String> get allKnownFinancialSenderAliases => financialSenderAliasesByProvider
    .values
    .expand((aliases) => aliases)
    .toList(growable: false);

bool isKnownFinancialSender(String sender) {
  return detectFinancialProvider(sender) != null;
}

String? detectFinancialProvider(String sender) {
  final normalizedSender = _normalizeFinancialSender(sender);
  for (final entry in financialSenderAliasesByProvider.entries) {
    for (final alias in entry.value) {
      if (normalizedSender.contains(alias)) {
        return entry.key;
      }
    }
  }
  return null;
}
