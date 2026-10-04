import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/user.dart';
import 'core_providers.dart';

class AuthSnapshot {
  const AuthSnapshot({this.session, this.profile, this.loading = false, this.isGuest = false});
  final Session? session;
  final AppUser? profile;
  final bool loading;

  /// « Continuer comme visiteur » : accès au simulateur de prix et au support.
  final bool isGuest;

  bool get isSignedIn => session != null && profile != null;

  AuthSnapshot copyWith({Session? session, AppUser? profile, bool? loading, bool? isGuest, bool clearProfile = false}) =>
      AuthSnapshot(
        session: session ?? this.session,
        profile: clearProfile ? null : (profile ?? this.profile),
        loading: loading ?? this.loading,
        isGuest: isGuest ?? this.isGuest,
      );
}

class AuthController extends Notifier<AuthSnapshot> {
  StreamSubscription<AuthState>? _sub;

  @override
  AuthSnapshot build() {
    final repo = ref.watch(authRepositoryProvider);
    _sub?.cancel();
    _sub = repo.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut) {
        ref.read(pushServiceProvider).stop();
        state = const AuthSnapshot();
      } else if (event.session != null &&
          (event.event == AuthChangeEvent.signedIn ||
              event.event == AuthChangeEvent.initialSession ||
              event.event == AuthChangeEvent.userUpdated)) {
        _loadProfile(event.session!);
      }
    });
    ref.onDispose(() => _sub?.cancel());

    final session = repo.session;
    if (session != null) {
      Future.microtask(() => _loadProfile(session));
      return AuthSnapshot(session: session, loading: true);
    }
    return const AuthSnapshot();
  }

  Future<void> _loadProfile(Session session) async {
    state = state.copyWith(session: session, loading: state.profile == null);
    try {
      final profile = await ref.read(authRepositoryProvider).fetchProfile();
      if (profile == null || !profile.isActive) {
        await ref.read(authRepositoryProvider).signOut();
        state = const AuthSnapshot();
        return;
      }
      state = AuthSnapshot(session: session, profile: profile);
      unawaited(ref.read(pushServiceProvider).start(profile.id));
    } catch (_) {
      // Hors connexion : on garde la session, le profil sera rechargé au retour du réseau.
      final cached = ref.read(cacheProvider).get<Map>('profile:${session.user.id}');
      state = AuthSnapshot(
        session: session,
        profile: cached == null ? null : AppUser.fromJson(Map<String, dynamic>.from(cached)),
      );
      if (cached == null) {
        Future.delayed(const Duration(seconds: 5), () {
          if (ref.mounted && state.profile == null && state.session != null) _loadProfile(session);
        });
      }
      return;
    }
    await ref.read(cacheProvider).put('profile:${session.user.id}', state.profile!.toJson());
  }

  Future<void> refreshProfile() async {
    final s = state.session;
    if (s != null) await _loadProfile(s);
  }

  void setProfile(AppUser profile) {
    state = state.copyWith(profile: profile);
    ref.read(cacheProvider).put('profile:${profile.id}', profile.toJson());
  }

  void continueAsGuest() => state = const AuthSnapshot(isGuest: true);
  void leaveGuest() => state = const AuthSnapshot();

  Future<void> signOut() async {
    await ref.read(pushServiceProvider).stop();
    await ref.read(pushServiceProvider).unregister();
    await ref.read(authRepositoryProvider).signOut();
    await ref.read(cacheProvider).clearAll();
    state = const AuthSnapshot();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthSnapshot>(AuthController.new);

final currentUserProvider = Provider<AppUser?>((ref) => ref.watch(authControllerProvider).profile);
