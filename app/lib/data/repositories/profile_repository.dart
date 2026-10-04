import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/config_models.dart';
import '../models/enums.dart';
import '../models/user.dart';

/// Profil, comptes professionnels et carnet d'adresses.
class ProfileRepository {
  ProfileRepository(this._client);
  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  Future<AppUser> updateProfile({required String fullName, String? cityId, String? avatarUrl}) async {
    final res = await _client.rpc('update_my_profile', params: {
      'p_full_name': fullName,
      'p_city_id': cityId,
      'p_avatar_url': avatarUrl,
    });
    return AppUser.fromJson(Map<String, dynamic>.from(res as Map));
  }

  // ---- Comptes professionnels ----
  Future<List<BusinessAccount>> myBusinesses() async {
    final rows = await _client.from('business_accounts').select().order('created_at');
    return rows.map(BusinessAccount.new).toList();
  }

  Future<BusinessAccount> createBusiness(Map<String, dynamic> data) async {
    final res = await _client.rpc('create_business_account', params: {'p': data});
    return BusinessAccount(Map<String, dynamic>.from(res as Map));
  }

  Future<void> updateBusiness(String id, Map<String, dynamic> data) =>
      _client.from('business_accounts').update(data).eq('id', id);

  Future<List<BusinessMember>> members(String businessId) async {
    final rows = await _client.from('business_members').select('*, users(full_name, phone)').eq('business_id', businessId);
    return rows.map(BusinessMember.new).toList();
  }

  Future<void> addMember(String businessId, String phone, MemberRole role) => _client.rpc('add_business_member',
      params: {'p_business_id': businessId, 'p_phone': phone, 'p_role': role.name});

  Future<void> removeMember(String businessId, String userId) =>
      _client.from('business_members').delete().eq('business_id', businessId).eq('user_id', userId);

  Future<Map<String, dynamic>> businessSummary(String businessId, DateTime from, DateTime to) async {
    final res = await _client.rpc('get_business_summary', params: {
      'p_business_id': businessId,
      'p_from': from.toUtc().toIso8601String(),
      'p_to': to.toUtc().toIso8601String(),
    });
    return Map<String, dynamic>.from(res as Map);
  }

  // ---- Adresses / clients enregistrés ----
  Future<List<SavedAddress>> savedAddresses({String? businessId}) async {
    var q = _client.from('saved_addresses').select();
    q = businessId != null ? q.eq('business_id', businessId) : q.eq('user_id', _uid!);
    final rows = await q.order('label');
    return rows.map(SavedAddress.new).toList();
  }

  Future<void> saveAddress(Map<String, dynamic> data, {String? businessId}) => _client.from('saved_addresses').upsert({
        ...data,
        if (businessId != null) 'business_id': businessId else 'user_id': _uid,
      });

  Future<void> deleteAddress(String id) => _client.from('saved_addresses').delete().eq('id', id);
}
