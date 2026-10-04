import 'package:flutter/material.dart';

import '../../config/theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.delivery_dining_rounded, size: 80, color: Colors.white),
            SizedBox(height: 16),
            Text('Telima', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
            SizedBox(height: 24),
            CircularProgressIndicator(color: Colors.white),
          ]),
        ),
      );
}

class ConfigMissingScreen extends StatelessWidget {
  const ConfigMissingScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.settings_suggest, size: 64, color: AppColors.accent),
              SizedBox(height: 16),
              Text('Configuration Supabase manquante', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              SizedBox(height: 12),
              SelectableText(
                'Lancez l\'application avec :\n\n'
                'flutter run --dart-define-from-file=env.json\n\n'
                'où env.json contient SUPABASE_URL et SUPABASE_ANON_KEY (voir README).',
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      );
}
