import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../providers/core_providers.dart';

/// Messages automatiques (SMS et WhatsApp) : nouvelle commande → administrateur, course acceptée → livreur,
/// livreur trouvé / colis en route / livraison terminée → client. Les identifiants WhatsApp ne sont jamais relus.
class OrderMessagingCard extends ConsumerStatefulWidget {
  const OrderMessagingCard({super.key});
  @override
  ConsumerState<OrderMessagingCard> createState() => _OrderMessagingCardState();
}

class _OrderMessagingCardState extends ConsumerState<OrderMessagingCard> {
  Map<String, dynamic>? _set;
  Map<String, dynamic>? _wa;
  bool _busy = false;
  final _adminPhone = TextEditingController();
  final _phoneId = TextEditingController();
  final _token = TextEditingController();
  final _template = TextEditingController();
  final _testPhone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_adminPhone, _phoneId, _token, _template, _testPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _load() async {
    try {
      final db = ref.read(supabaseProvider);
      final s = Map<String, dynamic>.from(await db.rpc('admin_get_order_messaging') as Map);
      final w = Map<String, dynamic>.from(await db.rpc('admin_whatsapp_status') as Map);
      if (!mounted) return;
      setState(() {
        _set = s;
        _wa = w;
        if (_adminPhone.text.isEmpty) _adminPhone.text = (s['admin_phone'] ?? '') as String;
        if (_phoneId.text.isEmpty) _phoneId.text = (w['phone_number_id'] ?? '') as String;
        if (_template.text.isEmpty) _template.text = (w['template'] ?? '') as String;
      });
    } catch (_) {
      if (mounted) _msg('Réglages des messages indisponibles');
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      _msg('Erreur : ${e.toString().replaceAll('PostgrestException(message: ', '').split(',').first}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSettings(Map<String, dynamic> patch) => _run(() async {
        final r = await ref.read(supabaseProvider).rpc('admin_set_order_messaging', params: {'p_settings': patch});
        if (mounted) setState(() => _set = Map<String, dynamic>.from(r as Map));
      });

  Future<void> _saveWhatsapp() => _run(() async {
        await ref.read(supabaseProvider).rpc('admin_set_whatsapp_gateway', params: {
          'p_phone_number_id': _phoneId.text,
          'p_access_token': _token.text,
          'p_template': _template.text,
        });
        _token.clear();
        _msg('WhatsApp enregistré');
        await _load();
      });

  Future<void> _test() => _run(() async {
        if (_testPhone.text.trim().length < 8) {
          _msg('Saisissez un numéro (ex. 22670123456)');
          return;
        }
        final ok = await ref.read(supabaseProvider).rpc('admin_send_test_whatsapp', params: {'p_phone': _testPhone.text.trim()});
        _msg(ok == true ? 'Message de test envoyé, vérifiez le statut ci-dessous' : 'WhatsApp non configuré');
        await Future<void>.delayed(const Duration(seconds: 3));
        await _load();
      });

  @override
  Widget build(BuildContext context) {
    final s = _set;
    final w = _wa;
    if (s == null) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Chargement…')));
    bool on(String k) => s[k] == true;
    Widget sw(String k, String label, {String? sub}) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(label),
          subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 12)),
          value: on(k),
          onChanged: _busy ? null : (v) => _saveSettings({k: v}),
        );
    final recent = (w?['recent'] as List?) ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sw('enabled', 'Envoyer des messages automatiques', sub: 'Désactivé par défaut. Chaque SMS est facturé par SMSBus.'),
          const Divider(),
          const Text('Canaux', style: TextStyle(fontWeight: FontWeight.w700)),
          sw('sms', 'SMS', sub: 'Utilise la passerelle SMSBus ci-dessous (mode « Fournisseur SMS configuré »).'),
          sw('whatsapp', 'WhatsApp', sub: 'Utilise l’API WhatsApp Cloud (réglages plus bas).'),
          const Divider(),
          const Text('Qui reçoit quoi', style: TextStyle(fontWeight: FontWeight.w700)),
          sw('admin', 'Moi (administrateur) : nouvelle commande'),
          sw('driver', 'Livreur : course acceptée'),
          sw('driver_requests', 'Livreurs : chaque nouvelle demande', sub: 'Beaucoup de messages : un par livreur concerné.'),
          sw('client', 'Client : livreur trouvé, colis en route, livraison terminée'),
          const SizedBox(height: 8),
          TextField(
            controller: _adminPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Autre numéro pour les nouvelles commandes (facultatif)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _busy ? null : () => _saveSettings({'admin_phone': _adminPhone.text.trim()}), child: const Text('Enregistrer ce numéro')),
          const Divider(height: 28),
          const Text('WhatsApp (API Cloud de Meta)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            w == null
                ? 'Chargement…'
                : (w['configured'] == true
                    ? 'Connecté · clé ${w['token_hint']} · ${w['sent']} envoyés, ${w['failed']} échecs'
                    : 'Non configuré'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(controller: _phoneId, decoration: const InputDecoration(labelText: 'Identifiant du numéro WhatsApp (Phone number ID)')),
          const SizedBox(height: 8),
          TextField(controller: _token, obscureText: true, decoration: const InputDecoration(labelText: 'Jeton d’accès (laisser vide pour conserver)')),
          const SizedBox(height: 8),
          TextField(
            controller: _template,
            decoration: const InputDecoration(
              labelText: 'Nom du modèle de message approuvé par Meta',
              helperText: 'Modèle avec une seule variable {{1}} dans le texte. Sans modèle, seuls les clients ayant écrit depuis 24 h reçoivent le message.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _saveWhatsapp, child: const Text('Enregistrer WhatsApp')),
          const Divider(height: 28),
          TextField(controller: _testPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Numéro pour un test WhatsApp (ex. 22670123456)')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _busy ? null : _test, child: const Text('Envoyer un message WhatsApp de test')),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final r in recent)
              Text('${r['status'] == 'sent' ? '✓' : r['status'] == 'failed' ? '✗' : '…'} ${r['phone']} · ${r['purpose']} · ${r['response'] ?? 'en cours'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ]),
      ),
    );
  }
}
