import 'enums.dart';
import 'json.dart';

class AppUser {
  AppUser({
    required this.id,
    required this.phone,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.cityId,
    this.avatarUrl,
    this.createdAt,
  });

  final String id;
  final String phone;
  final String fullName;
  final UserRole role;
  final bool isActive;
  final String? cityId;
  final String? avatarUrl;
  final DateTime? createdAt;

  String get firstName => fullName.split(' ').first;

  factory AppUser.fromJson(Json j) => AppUser(
        id: j['id'] as String,
        phone: j['phone'] as String,
        fullName: j['full_name'] as String? ?? '',
        role: UserRole.parse(j['role'] as String?),
        isActive: asBool(j['is_active'], true),
        cityId: j['city_id'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        createdAt: asDate(j['created_at']),
      );

  Json toJson() => {
        'id': id,
        'phone': phone,
        'full_name': fullName,
        'role': role.name,
        'is_active': isActive,
        'city_id': cityId,
        'avatar_url': avatarUrl,
        'created_at': createdAt?.toIso8601String(),
      };
}
