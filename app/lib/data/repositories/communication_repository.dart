import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/config_models.dart';
import '../models/delivery.dart';

/// Messagerie client/livreur, notifications et support.
class CommunicationRepository {
  CommunicationRepository(this._client);
  final SupabaseClient _client;

  String? get uid => _client.auth.currentUser?.id;

  Stream<List<ChatMessage>> watchMessages(String deliveryId) => _client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('delivery_id', deliveryId)
      .order('created_at')
      .map((rows) => rows.map(ChatMessage.fromJson).toList());

  Future<void> sendMessage(String deliveryId, String body) =>
      _client.from('messages').insert({'delivery_id': deliveryId, 'sender_id': uid, 'body': body.trim()});

  Future<void> markMessagesRead(String deliveryId) => _client
      .from('messages')
      .update({'read_at': DateTime.now().toUtc().toIso8601String()})
      .eq('delivery_id', deliveryId)
      .neq('sender_id', uid!)
      .isFilter('read_at', null);

  Stream<List<AppNotification>> watchNotifications() => _client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', uid!)
      .order('created_at', ascending: false)
      .limit(100)
      .map((rows) => rows.map(AppNotification.new).toList());

  Future<void> markAllNotificationsRead() => _client.rpc('mark_notifications_read');

  Future<void> markNotificationRead(int id) => _client.rpc('mark_notifications_read', params: {
        'p_ids': [id]
      });

  Future<void> deleteNotification(int id) => _client.from('notifications').delete().eq('id', id);

  Future<void> sendSupportRequest({required String subject, required String message, String? phone, String? deliveryId}) =>
      _client.from('support_requests').insert({
        'user_id': uid,
        'phone': phone,
        'subject': subject,
        'message': message,
        'delivery_id': deliveryId,
      });

  Future<List<SupportRequest>> mySupportRequests() async {
    if (uid == null) return [];
    final rows = await _client.from('support_requests').select().eq('user_id', uid!).order('created_at', ascending: false);
    return rows.map(SupportRequest.new).toList();
  }
}
