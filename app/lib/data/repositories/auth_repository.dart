import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/formatters.dart';
import '../models/user.dart';

/// Authentification par téléphone + mot de passe.
/// Le numéro est l'identifiant principal ; il est converti en identifiant technique pour Supabase Auth.
class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  Session? get session => _client.auth.currentSession;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signIn({required String phone, required String password}) async {
    await _client.auth.signInWithPassword(email: phoneToAuthEmail(phone), password: password);
    final profile = await fetchProfile();
    if (profile == null || !profile.isActive) {
      await _client.auth.signOut();
      throw Exception('Ce compte est désactivé. Contactez le support.');
    }
  }

  Future<void> signUp({
    required String phone,
    required String password,
    required String fullName,
    String? cityId,
    bool asDriver = false,
  }) async {
    final normalized = normalizePhone(phone);
    // Création du compte côté serveur (fonction Edge telima-signup) : l'identifiant technique
    // n'est pas une vraie boîte mail, aucun e-mail de confirmation n'est donc envoyé.
    final res = await _client.functions.invoke('telima-signup', body: {
      'phone': normalized,
      'password': password,
      'full_name': fullName.trim(),
      'city_id': cityId,
      'role': asDriver ? 'driver' : 'client',
    });
    final data = res.data;
    if (data is Map && data['error'] != null) throw Exception(data['error']);
    await _client.auth.signInWithPassword(email: phoneToAuthEmail(normalized), password: password);
  }

  Future<AppUser?> fetchProfile() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client.from('users').select().eq('id', uid).maybeSingle();
    return row == null ? null : AppUser.fromJson(row);
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> changePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Étape 1 de la récupération : un code est envoyé par SMS
  /// (en mode simulation, il est transmis à l'administration qui le communique au client).
  Future<bool> requestPasswordReset(String phone) async {
    final res = await _client.rpc('request_password_reset', params: {'p_phone': normalizePhone(phone)});
    return (res as Map)['simulation'] == true;
  }

  /// Étape 2 : vérification du code et nouveau mot de passe (fonction Edge reset-password).
  Future<void> resetPassword({required String phone, required String code, required String newPassword}) async {
    await _client.functions.invoke('reset-password', body: {
      'phone': normalizePhone(phone),
      'code': code.trim(),
      'new_password': newPassword,
    });
  }

  Future<void> deactivateAccount() async {
    final uid = _client.auth.currentUser?.id;
    if (uid != null) {
      // retire les jetons de notification de cet utilisateur (autorisé par la RLS device_tokens_own)
      await _client.from('device_tokens').delete().eq('user_id', uid);
    }
    await _client.rpc('deactivate_my_account');
    await _client.auth.signOut();
  }
}
