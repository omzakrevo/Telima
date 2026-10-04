/// Aides de conversion JSON tolérantes (PostgREST renvoie parfois des numériques en chaîne).
typedef Json = Map<String, dynamic>;

double? asDouble(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
int asInt(dynamic v, [int fallback = 0]) =>
    v == null ? fallback : (v is num ? v.round() : (num.tryParse(v.toString())?.round() ?? fallback));
DateTime? asDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
bool asBool(dynamic v, [bool fallback = false]) => v == null ? fallback : (v is bool ? v : v.toString() == 'true');
String? asStr(dynamic v) => v?.toString();
