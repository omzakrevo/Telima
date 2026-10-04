import 'package:intl/intl.dart';

import '../../config/env.dart';

final _fcfa = NumberFormat.decimalPattern('fr_FR');

/// 1500 → « 1 500 FCFA »
String fcfa(num? value) => '${_fcfa.format((value ?? 0).round()).replaceAll(' ', ' ').replaceAll(' ', ' ')} FCFA';

/// 6.2 → « 6,2 km »
String km(num? value) {
  final v = (value ?? 0).toDouble();
  if (v < 1) return '${(v * 1000).round()} m';
  return '${v.toStringAsFixed(1).replaceAll('.', ',')} km';
}

String minutes(num? value) {
  final v = (value ?? 0).round();
  if (v < 60) return '$v min';
  return '${v ~/ 60} h ${(v % 60).toString().padLeft(2, '0')}';
}

final _dateTime = DateFormat('dd/MM/yyyy HH:mm', 'fr_FR');
final _date = DateFormat('dd/MM/yyyy', 'fr_FR');
final _time = DateFormat('HH:mm', 'fr_FR');
final _dayShort = DateFormat('dd/MM', 'fr_FR');

String formatDateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d.toLocal());
String formatDate(DateTime? d) => d == null ? '—' : _date.format(d.toLocal());
String formatTime(DateTime? d) => d == null ? '—' : _time.format(d.toLocal());
String formatDayShort(DateTime? d) => d == null ? '' : _dayShort.format(d.toLocal());

String relativeTime(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inSeconds < 60) return 'à l\'instant';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  return formatDateTime(d);
}

/// Normalise un numéro burkinabè : « 70 12 34 56 » → « +22670123456 ».
String normalizePhone(String input) {
  var v = input.replaceAll(RegExp(r'[^0-9+]'), '');
  if (v.startsWith('00')) v = '+${v.substring(2)}';
  if (RegExp(r'^[0-9]{8}$').hasMatch(v)) v = '+226$v';
  if (RegExp(r'^226[0-9]{8}$').hasMatch(v)) v = '+$v';
  return v;
}

bool isValidPhone(String input) => RegExp(r'^\+[0-9]{8,15}$').hasMatch(normalizePhone(input));

/// Le numéro de téléphone est l'identifiant ; Supabase Auth reçoit une adresse technique dérivée.
String phoneToAuthEmail(String phone) => '${normalizePhone(phone).replaceAll('+', '')}@${Env.authEmailDomain}';

/// +22670123456 → « +226 70 12 34 56 »
String displayPhone(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  final m = RegExp(r'^\+226(\d{2})(\d{2})(\d{2})(\d{2})$').firstMatch(phone);
  if (m == null) return phone;
  return '+226 ${m.group(1)} ${m.group(2)} ${m.group(3)} ${m.group(4)}';
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}
