import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/env.dart';
import '../../data/models/config_models.dart';

/// Notifications Telima.
///
/// Chaque événement est écrit côté serveur dans `notifications` (déclencheurs SQL), puis :
///  * application ouverte ou en arrière-plan : reçu en temps réel et affiché en bannière système ;
///  * application fermée : le serveur l'envoie par Firebase Cloud Messaging (fonction `telima-push`),
///    Android l'affiche lui-même en bannière.
/// Les deux chemins utilisent la même étiquette (`telima-<id>`) : Android remplace l'une par l'autre,
/// jamais de doublon.
class SystemNotifications {
  SystemNotifications._();

  static const channelId = 'telima_alerts';
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Page à ouvrir quand l'utilisateur touche une notification (renseigné par l'application).
  static void Function(String route)? onOpen;
  static String? _pendingRoute;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String tagFor(int id) => 'telima-$id';

  static String routeFor(String? type, Map data) {
    final delivery = data['delivery_id']?.toString();
    if (type == 'message' && delivery != null) return '/chat/$delivery';
    return '/notifications';
  }

  /// À appeler au démarrage : crée le canal « Alertes Telima » (bannière en haut de l'écran, son,
  /// vibration) et demande l'autorisation d'afficher les notifications (Android 13 et plus).
  static Future<void> init() async {
    if (!supported || _ready) return;
    _ready = true;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_telima')),
      onDidReceiveNotificationResponse: (r) => _open(r.payload),
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      channelId,
      'Alertes Telima',
      description: 'Courses, livraisons, messages et paiements',
      importance: Importance.max,
    ));
    await android?.requestNotificationsPermission();
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) _open(launch!.notificationResponse?.payload);
  }

  /// Les notifications sont-elles autorisées sur ce téléphone ?
  static Future<bool> enabled() async {
    if (!supported) return true;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? true;
  }

  static Future<bool> requestPermission() async {
    if (!supported) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  static void _open(String? route) {
    if (route == null || route.isEmpty) return;
    if (onOpen != null) {
      onOpen!(route);
    } else {
      _pendingRoute = route;
    }
  }

  /// Ouvre la page demandée par une notification touchée avant que l'application soit prête.
  static void flushPending() {
    final r = _pendingRoute;
    _pendingRoute = null;
    if (r != null) _open(r);
  }

  static Future<void> show(AppNotification n) async {
    if (!supported) return;
    await init();
    await _plugin.show(
      id: 0,
      title: n.title,
      body: n.body,
      payload: routeFor(n.type, n.data),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Alertes Telima',
          channelDescription: 'Courses, livraisons, messages et paiements',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_stat_telima',
          color: const Color(0xFF3D8B5F),
          tag: tagFor(n.id),
          styleInformation: BigTextStyleInformation(n.body),
          category: AndroidNotificationCategory.message,
        ),
      ),
    );
  }
}

/// Transport des notifications « application fermée ».
abstract class PushTransport {
  Future<String?> obtainToken();
  Stream<String> get tokenRefresh => const Stream.empty();
}

class NoopPushTransport implements PushTransport {
  @override
  Future<String?> obtainToken() async => null;
  @override
  Stream<String> get tokenRefresh => const Stream.empty();
}

/// Firebase Cloud Messaging. La configuration Firebase est lue dans `app_settings` (clé `firebase`),
/// elle peut donc être ajoutée ou changée sans republier l'application.
class FcmPushTransport implements PushTransport {
  FcmPushTransport(this._client);
  final SupabaseClient _client;
  bool _initialized = false;

  Future<bool> _ensureFirebase() async {
    if (_initialized) return true;
    if (Firebase.apps.isNotEmpty) return _initialized = true;
    final row = await _client.from('app_settings').select('value').eq('key', 'firebase').maybeSingle();
    final v = row?['value'];
    if (v is! Map || (v['apiKey'] ?? '').toString().isEmpty) return false;
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: v['apiKey'].toString(),
        appId: v['appId'].toString(),
        messagingSenderId: v['messagingSenderId'].toString(),
        projectId: v['projectId'].toString(),
        storageBucket: v['storageBucket']?.toString(),
      ),
    );
    // Notification touchée alors que l'application était fermée / en arrière-plan
    FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _openFromMessage(initial);
    return _initialized = true;
  }

  void _openFromMessage(RemoteMessage m) {
    final route = m.data['route']?.toString();
    if (route != null) SystemNotifications._open(route);
  }

  @override
  Future<String?> obtainToken() async {
    if (!SystemNotifications.supported) return null;
    try {
      if (!await _ensureFirebase()) return null;
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('FCM indisponible : $e');
      return null;
    }
  }

  @override
  Stream<String> get tokenRefresh => _initialized ? FirebaseMessaging.instance.onTokenRefresh : const Stream.empty();
}

/// Petit bandeau dans l'application (version web, où il n'y a pas de notifications système).
class InAppNotifier {
  InAppNotifier(this.messengerKey);
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  void Function(AppNotification n)? onTap;

  void show(AppNotification n) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Row(children: [
        const Icon(Icons.notifications_active, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(n.body),
          ]),
        ),
      ]),
      action: onTap == null ? null : SnackBarAction(label: 'VOIR', onPressed: () => onTap!(n)),
    ));
  }
}

class PushService {
  PushService(this._client, this._notifier, {PushTransport? transport})
      : _transport = transport ?? (SystemNotifications.supported ? FcmPushTransport(_client) : NoopPushTransport());
  final SupabaseClient _client;
  final InAppNotifier _notifier;
  final PushTransport _transport;
  RealtimeChannel? _channel;
  StreamSubscription<String>? _refresh;
  String? _token;

  String? get token => _token;

  Future<void> start(String userId) async {
    await stop();
    _channel = _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: Env.dbSchema,
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId),
          callback: (payload) {
            final n = AppNotification(payload.newRecord);
            if (SystemNotifications.supported) {
              SystemNotifications.show(n);
            } else {
              _notifier.show(n);
            }
          },
        )
        .subscribe();
    try {
      final token = await _transport.obtainToken();
      if (token != null) {
        await _register(token);
        _refresh = _transport.tokenRefresh.listen(_register);
      }
    } catch (e) {
      debugPrint('Enregistrement push impossible : $e');
    }
  }

  Future<void> _register(String token) async {
    _token = token;
    await _client.rpc('register_device_token', params: {'p_token': token, 'p_platform': 'android'});
  }

  Future<void> stop() async {
    await _refresh?.cancel();
    _refresh = null;
    if (_channel != null) {
      await _client.removeChannel(_channel!);
      _channel = null;
    }
  }

  /// À la déconnexion : ce téléphone ne doit plus recevoir les notifications du compte.
  Future<void> unregister() async {
    final t = _token;
    _token = null;
    if (t == null) return;
    try {
      await _client.from('device_tokens').delete().eq('token', t);
    } catch (_) {}
  }
}
