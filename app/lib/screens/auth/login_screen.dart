import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/validators.dart';
import '../../providers/core_providers.dart';
import '../../config/theme.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).signIn(phone: _phone.text, password: _password.text);
      // la redirection est faite par le routeur dès que le profil est chargé
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white),
      body: Constrained(
        maxWidth: 440,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
            const Center(child: BrandMark(size: 40, animate: true)),
            const SizedBox(height: 28),
            const Text('Connexion', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Connectez-vous pour gérer vos livraisons. Pas de compte ? ',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
              InkWell(
                onTap: () => context.pushReplacement('/register'),
                child: const Text('Inscrivez-vous',
                    style: TextStyle(color: AppColors.primary, fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 28),
            const _FieldLabel('Numéro de téléphone'),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: const InputDecoration(hintText: '70 12 34 56', prefixIcon: Icon(Icons.phone_rounded)),
              validator: Validators.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            const _FieldLabel('Mot de passe'),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                hintText: 'Votre mot de passe',
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Afficher' : 'Masquer',
                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: Validators.password,
              onFieldSubmitted: (_) => _submit(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => context.push('/forgot'), child: const Text('Mot de passe oublié ?')),
            ),
            const SizedBox(height: 8),
            BigActionButton(label: 'Se connecter', onPressed: _submit, loading: _loading),
            const SizedBox(height: 22),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Vous êtes livreur ? ', style: TextStyle(color: AppColors.textMuted)),
              InkWell(
                onTap: () => context.pushReplacement('/register?driver=1'),
                child: const Text('Rejoignez-nous', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      );
}
