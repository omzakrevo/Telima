import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/validators.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';

/// Récupération du compte : code à 6 chiffres reçu par SMS (ou communiqué par le support en mode simulation).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _simulation = false;
  bool _loading = false;

  Future<void> _request() async {
    if (Validators.phone(_phone.text) != null) {
      _form.currentState!.validate();
      return;
    }
    setState(() => _loading = true);
    try {
      _simulation = await ref.read(authRepositoryProvider).requestPasswordReset(_phone.text);
      setState(() => _codeSent = true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).resetPassword(phone: _phone.text, code: _code.text, newPassword: _password.text);
      if (!mounted) return;
      showSuccess(context, 'Mot de passe modifié. Connectez-vous.');
      context.pushReplacement('/login');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Récupérer mon compte')),
      body: Constrained(
        maxWidth: 480,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            TextFormField(
              controller: _phone,
              enabled: !_codeSent,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: const InputDecoration(labelText: 'Téléphone du compte', prefixIcon: Icon(Icons.phone)),
              validator: Validators.phone,
            ),
            const SizedBox(height: 16),
            if (!_codeSent)
              BigActionButton(label: 'Recevoir un code', onPressed: _request, loading: _loading)
            else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(_simulation
                      ? 'Votre demande a été transmise au support. Appelez le ${settings?.supportPhone ?? 'support'} '
                          'pour recevoir votre code à 6 chiffres (valable 30 minutes).'
                      : 'Un code à 6 chiffres vous a été envoyé par SMS (valable 30 minutes).'),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Code reçu', prefixIcon: Icon(Icons.pin)),
                validator: (v) => (v ?? '').length != 6 ? 'Code à 6 chiffres' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Nouveau mot de passe', prefixIcon: Icon(Icons.lock_outline)),
                validator: Validators.password,
              ),
              const SizedBox(height: 16),
              BigActionButton(label: 'Changer le mot de passe', onPressed: _reset, loading: _loading),
              TextButton(onPressed: _loading ? null : _request, child: const Text('Renvoyer un code')),
            ],
          ]),
        ),
      ),
    );
  }
}
