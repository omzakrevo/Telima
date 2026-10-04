import 'formatters.dart';

class Validators {
  static String? required(String? v, [String label = 'Ce champ']) =>
      (v == null || v.trim().isEmpty) ? '$label est obligatoire' : null;

  static String? name(String? v) {
    if (v == null || v.trim().length < 2) return 'Nom trop court';
    return null;
  }

  static String? phone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Téléphone obligatoire';
    if (!isValidPhone(v)) return 'Numéro invalide (ex. 70 12 34 56)';
    return null;
  }

  static String? optionalPhone(String? v) => (v == null || v.trim().isEmpty) ? null : phone(v);

  static String? password(String? v) {
    if (v == null || v.length < 6) return 'Au moins 6 caractères';
    return null;
  }

  static String? positiveInt(String? v, {int min = 1}) {
    final n = int.tryParse((v ?? '').replaceAll(' ', ''));
    if (n == null || n < min) return 'Valeur minimale : $min';
    return null;
  }

  static String? number(String? v, {double min = 0}) {
    final n = double.tryParse((v ?? '').replaceAll(',', '.').replaceAll(' ', ''));
    if (n == null || n < min) return 'Nombre invalide';
    return null;
  }
}
