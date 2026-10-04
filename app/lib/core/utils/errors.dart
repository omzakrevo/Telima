import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Message d'erreur compréhensible, en français, pour l'utilisateur.
String friendlyError(Object error) {
  if (error is PostgrestException) {
    final msg = error.message;
    if (error.code == 'PGRST301' || msg.contains('JWT')) return 'Session expirée, reconnectez-vous.';
    if (msg.contains('duplicate key')) return 'Cet élément existe déjà.';
    if (msg.contains('violates row-level security')) return 'Action non autorisée.';
    return msg;
  }
  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login credentials')) return 'Téléphone ou mot de passe incorrect.';
    if (m.contains('already registered') || m.contains('already been registered')) {
      return 'Un compte existe déjà avec ce numéro.';
    }
    if (m.contains('email not confirmed')) return 'Compte non confirmé. Contactez le support.';
    if (m.contains('password')) return 'Mot de passe invalide (6 caractères minimum).';
    return error.message;
  }
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map && details['error'] != null) return details['error'].toString();
    return 'Service indisponible (${error.status}).';
  }
  if (error is StorageException) return 'Envoi du fichier impossible : ${error.message}';
  if (error is TimeoutException) return 'La connexion est trop lente. Réessayez.';
  if (isNetworkError(error)) return 'Pas de connexion Internet. Réessayez.';
  final s = error.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

bool isNetworkError(Object error) {
  if (error is TimeoutException) return true;
  final s = error.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('clientexception') ||
      s.contains('xmlhttprequest') ||
      s.contains('network') ||
      s.contains('connection');
}
