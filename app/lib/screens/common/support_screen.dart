import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../core/utils/validators.dart';
import '../../data/models/config_models.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key, this.deliveryId, this.embedded = false});
  final String? deliveryId;
  final bool embedded;

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _form = GlobalKey<FormState>();
  final _message = TextEditingController();
  final _phone = TextEditingController();
  String _subject = 'Problème de livraison';
  bool _sending = false;

  static const _subjects = ['Problème de livraison', 'Paiement', 'Mon compte', 'Devenir livreur', 'Compte professionnel', 'Autre'];

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      final user = ref.read(currentUserProvider);
      await ref.read(communicationRepositoryProvider).sendSupportRequest(
            subject: _subject,
            message: _message.text.trim(),
            phone: user?.phone ?? normalizePhone(_phone.text),
            deliveryId: widget.deliveryId,
          );
      _message.clear();
      ref.invalidate(mySupportRequestsProvider);
      if (mounted) showSuccess(context, 'Message envoyé. Le support vous répondra rapidement.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final user = ref.watch(currentUserProvider);
    final requests = user == null ? const <SupportRequest>[] : ref.watch(mySupportRequestsProvider).value ?? const <SupportRequest>[];

    final body = Constrained(
      maxWidth: 640,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (settings != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Nous sommes là pour vous aider', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                if (settings.supportHours.isNotEmpty) Text(settings.supportHours, style: const TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 12),
                if (settings.supportPhone.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () => callPhone(settings.supportPhone),
                    icon: const Icon(Icons.call),
                    label: Text('Appeler ${displayPhone(settings.supportPhone)}'),
                  ),
                const SizedBox(height: 8),
                Row(children: [
                  if (settings.supportWhatsapp.isNotEmpty)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => openWhatsApp(settings.supportWhatsapp, 'Bonjour Telima, '),
                        icon: const Icon(Icons.chat),
                        label: const Text('WhatsApp'),
                      ),
                    ),
                  if (settings.supportEmail.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => sendEmail(settings.supportEmail, 'Support Telima'),
                        icon: const Icon(Icons.email_outlined),
                        label: const Text('E-mail'),
                      ),
                    ),
                  ],
                ]),
              ]),
            ),
          ),
        const SectionTitle('Écrire au support'),
        Form(
          key: _form,
          child: Column(children: [
            DropdownButtonFormField<String>(
              initialValue: _subject,
              decoration: const InputDecoration(labelText: 'Sujet'),
              items: [for (final s in _subjects) DropdownMenuItem(value: s, child: Text(s))],
              onChanged: (v) => setState(() => _subject = v ?? _subject),
            ),
            const SizedBox(height: 12),
            if (user == null) ...[
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: const InputDecoration(labelText: 'Votre téléphone (pour vous rappeler)'),
                validator: Validators.phone,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _message,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Votre message', alignLabelWithHint: true),
              validator: (v) => Validators.required(v, 'Le message'),
            ),
            const SizedBox(height: 12),
            BigActionButton(label: 'Envoyer', icon: Icons.send, onPressed: _send, loading: _sending),
          ]),
        ),
        if (requests.isNotEmpty) ...[
          const SectionTitle('Mes demandes'),
          for (final r in requests)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(r.subject, style: const TextStyle(fontWeight: FontWeight.w700))),
                      Pill(r.statusLabel, color: r.status == 'closed' ? AppColors.textMuted : AppColors.accent),
                    ]),
                    const SizedBox(height: 4),
                    Text(r.message),
                    Text(formatDateTime(r.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    if ((r.adminReply ?? '').isNotEmpty) ...[
                      const Divider(),
                      Text('Réponse : ${r.adminReply}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ],
                  ]),
                ),
              ),
            ),
        ],
      ]),
    );
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Support')), body: body);
  }
}
