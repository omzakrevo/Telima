import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/gas.dart';
import '../../providers/auth_providers.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/common.dart';
import 'gas_home_screen.dart';

/// Points de gaz et stations-service mis en favoris.
class FavoritePlacesScreen extends ConsumerWidget {
  const FavoritePlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    final async = ref.watch(favoritePlacesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes favoris')),
      body: !signedIn
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Connectez-vous pour retrouver vos favoris.', textAlign: TextAlign.center)))
          : AsyncBody<List<Place>>(
              value: async,
              onRetry: () => ref.invalidate(favoritePlacesProvider),
              builder: (list) => list.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Aucun favori pour le moment.\nAppuyez sur le cœur d’une fiche pour l’ajouter.', textAlign: TextAlign.center),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => ref.invalidate(favoritePlacesProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => PlaceCard(place: list[i]),
                      ),
                    ),
            ),
    );
  }
}
