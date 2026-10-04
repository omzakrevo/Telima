import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../providers/core_providers.dart';

/// Passerelle SMS SMSBus : statut, solde, envoi de test. L'identifiant API n'est jamais relu par l'application.
class SmsGatewayCard extends ConsumerStatefulWidget {
  const SmsGatewayCard({super.key});
  @override
  ConsumerState<SmsGatewayCard> createState() => _SmsGatewayCardState();
}

class _SmsGatewayCardState extends ConsumerState<SmsGatewayCard> {
  Map<String, dynamic>? _status;
  String? _balance;
  bool _busy = false;
  final _apiId = TextEditingController();
  final _sender = TextEditingController();
  final _testPhone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiId.dispose();
    _sender.dispose();
    _testPhone.dispose();
    super.dispose();
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _load() async {
    try {
      final r = await ref.read(supabaseProvider).rpc('admin_sms_status');
      if (!mounted) return;
      setState(() {
        _status = Map<String, dynamic>.from(r as Map);
        if (_sender.text.isEmpty) _sender.text = (_status!['sender_id'] ?? '') as String;
      });
    } catch (e) {
      if (mounted) _msg('Statut SMS indisponible');
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

  Future<void> _save() => _run(() async {
        await ref.read(supabaseProvider).rpc('admin_set_sms_gateway', params: {'p_api_id': _apiId.text, 'p_sender': _sender.text});
        _apiId.clear();
        _msg('Passerelle enregistrée');
        await _load();
      });

  Future<void> _checkBalance() => _run(() async {
        final db = ref.read(supabaseProvider);
        final id = await db.rpc('admin_sms_balance_request');
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          final r = await db.rpc('admin_sms_balance_result', params: {'p_request': id});
          if (r != null) {
            if (mounted) setState(() => _balance = (r as String).trim());
            return;
          }
        }
        _msg('Pas de réponse du fournisseur, réessayez.');
      });

  Future<void> _test() => _run(() async {
        if (_testPhone.text.trim().length < 8) {
          _msg('Saisissez un numéro (ex. 22670123456)');
          return;
        }
        final ok = await ref.read(supabaseProvider).rpc('admin_send_test_sms', params: {'p_phone': _testPhone.text.trim()});
        _msg(ok == true ? 'SMS de test envoyé, vérifiez le statut ci-dessous' : 'Passerelle non configurée');
        await Future<void>.delayed(const Duration(seconds: 3));
        await _load();
      });

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final recent = (s?['recent'] as List?) ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            s == null
                ? 'Chargement…'
                : (s['configured'] == true
                    ? 'Connectée · expéditeur ${s['sender_id']} · clé ${s['api_id_hint']} · ${s['sent']} envoyés, ${s['failed']} échecs'
                    : 'Non configurée'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text('Pour envoyer de vrais SMS, choisissez « Fournisseur SMS configuré » dans les paramètres ci-dessus.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(controller: _apiId, decoration: const InputDecoration(labelText: 'Identifiant API SMSBus (laisser vide pour conserver)')),
          const SizedBox(height: 8),
          TextField(controller: _sender, maxLength: 11, decoration: const InputDecoration(labelText: 'Expéditeur (11 caractères max)')),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Enregistrer')),
            OutlinedButton(onPressed: _busy ? null : _checkBalance, child: Text(_balance == null ? 'Voir le solde' : 'Solde : $_balance')),
          ]),
          const Divider(height: 28),
          TextField(controller: _testPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Numéro pour un SMS de test (ex. 22670123456)')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _busy ? null : _test, child: const Text('Envoyer un SMS de test')),
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
