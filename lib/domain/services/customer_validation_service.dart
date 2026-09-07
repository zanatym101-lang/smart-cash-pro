import '../../ai_sms/customer_matching_service.dart';

enum CustomerValidationResultType {
  valid,
  warning,
  error,
}

class CustomerValidationResult {
  final CustomerValidationResultType type;
  final String? message;

  const CustomerValidationResult(this.type, [this.message]);
  
  bool get isError => type == CustomerValidationResultType.error;
}

class CustomerValidationService {
  const CustomerValidationService();

  CustomerValidationResult validateCustomer({
    required String name,
    required String? note,
    required List<CustomerMatchCandidate> existingCustomers,
  }) {
    final inputName = name.trim().toLowerCase();
    
    String? normalizedInputPhone = _extractPhone('$name ${note ?? ''}');

    bool nameMatched = false;
    
    for (final existing in existingCustomers) {
      final existingName = existing.customerName.trim().toLowerCase();
      final existingPhone = existing.phone != null ? _normalizePhone(existing.phone!) : null;

      if (normalizedInputPhone != null && 
          normalizedInputPhone.isNotEmpty &&
          existingPhone != null && 
          existingPhone.isNotEmpty &&
          normalizedInputPhone == existingPhone) {
            
        if (inputName != existingName) {
           return CustomerValidationResult(
             CustomerValidationResultType.error,
             'هذا الرقم مسجل بالفعل باسم عميل آخر: ${existing.customerName}',
           );
        }
      }

      if (inputName == existingName) {
        if (normalizedInputPhone != null && 
            existingPhone != null && 
            normalizedInputPhone != existingPhone) {
          nameMatched = true;
        }
      }
    }

    if (nameMatched) {
      return const CustomerValidationResult(
        CustomerValidationResultType.warning,
        'يوجد عميل بنفس الاسم ولكن برقم هاتف مختلف. يرجى التأكد.',
      );
    }

    return const CustomerValidationResult(CustomerValidationResultType.valid);
  }

  String? _extractPhone(String input) {
    for (final match in RegExp(r'\+?\d[\d\s().-]{8,}\d').allMatches(input)) {
      final normalized = _normalizePhone(match.group(0) ?? '');
      if (normalized.length >= 10 && normalized.length <= 15) {
        return normalized;
      }
    }
    return null;
  }

  String _normalizePhone(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }
}
