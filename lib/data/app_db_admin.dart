part of 'app_db.dart';

const List<String> kDefaultQuickActionsOrder = [
  'help',
  'transfer',
  'receive',
  'fawry',
  'wallets',
  'treasury',
  'pending',
  'reports',
  'expenses',
  'claims',
  'wallet_funding',
];

extension AppDbAdmin on AppDb {
  void _requireAdmin() {
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/king_wallet_settings.json');
  }

  Future<Map<String, dynamic>> _readSettingsMap() async {
    final f = await _settingsFile();
    if (!await f.exists()) return {};
    try {
      final raw = await f.readAsString();
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) {
        return Map<String, dynamic>.from(m);
      }
    } catch (_) {}
    return {};
  }

  Future<void> _writeSettingsMap(Map<String, dynamic> m) async {
    final f = await _settingsFile();
    await f.writeAsString(jsonEncode(m));
  }

  Future<Map<String, dynamic>> readRawSettingsMap() async => _readSettingsMap();

  Future<void> writeRawSettingsMap(Map<String, dynamic> settings) async {
    await _writeSettingsMap(settings);
  }
}
