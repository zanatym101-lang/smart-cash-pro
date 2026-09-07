import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/utils/phone_provider.dart';

void main() {
  group('PhoneProvider and Normalizer Tests', () {
    test('normalizes English and Arabic-Indic phone numbers properly', () {
      expect(normalizePhone('01012345678'), '01012345678');
      expect(normalizePhone('٠١٠١٢٣٤٥٦٧٨'), '01012345678');
      expect(normalizePhone('+20 10 1234 5678'), '201012345678');
      expect(normalizePhone('00201012345678'), '00201012345678');
    });

    test('detects correct Egyptian carriers', () {
      expect(providerFromPhone('01011112222'), 'vodafone');
      expect(providerFromPhone('201011112222'), 'vodafone');
      expect(providerFromPhone('+201011112222'), 'vodafone');
      expect(providerFromPhone('00201011112222'), 'vodafone');

      expect(providerFromPhone('01111112222'), 'etisalat');
      expect(providerFromPhone('201111112222'), 'etisalat');

      expect(providerFromPhone('01211112222'), 'orange');
      expect(providerFromPhone('201211112222'), 'orange');

      expect(providerFromPhone('01511112222'), 'we');
      expect(providerFromPhone('201511112222'), 'we');

      expect(providerFromPhone('01911112222'), 'unknown');
      expect(providerFromPhone('12345'), 'unknown');
    });

    test('provides accurate display names in Arabic', () {
      expect(providerDisplayName('vodafone'), 'فودافون');
      expect(providerDisplayName('etisalat'), 'اتصالات');
      expect(providerDisplayName('orange'), 'أورنج');
      expect(providerDisplayName('we'), 'وي');
      expect(providerDisplayName('other'), 'غير معروف');
    });
  });
}
