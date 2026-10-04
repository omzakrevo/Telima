import 'package:flutter/material.dart';

/// Palette Telima — style « vert sauge » : fond blanc légèrement mentholé, cartes teintées vert pâle,
/// boutons verts aux coins arrondis, barre de navigation flottante sombre.
class AppColors {
  static const primary = Color(0xFF3D8B5F); // vert Telima
  static const primaryDark = Color(0xFF2B6B48);
  static const ink = Color(0xFF1C2420); // titres, barre de navigation
  static const accent = Color(0xFFF08A3C); // orange (point d'arrivée, étoiles)
  static const danger = Color(0xFFDC4B4B);
  static const info = Color(0xFF3F6FD8);
  static const surface = Color(0xFFF6FAF7); // fond des écrans
  static const field = Color(0xFFEDF4EF); // lignes de liste, puces, cartes teintées
  static const line = Color(0xFFE1EBE4); // bordures discrètes
  static const textMuted = Color(0xFF7A8580);
  static const backdrop = Color(0xFFDDEDE3); // fond vert pâle (en-têtes, accueil)

  // Tons doux pour les illustrations de services
  static const mint = Color(0xFFE0F0E6);
  static const peach = Color(0xFFFFEBDD);
  static const lilac = Color(0xFFECE8FA);
  static const sky = Color(0xFFE3EEFC);
  static const butter = Color(0xFFFFF5D6);
  static const rose = Color(0xFFFCE6E8);
}

/// Ombres douces (profondeur des cartes).
class AppShadows {
  static List<BoxShadow> get soft => const [
        BoxShadow(color: Color(0x142B6B48), blurRadius: 18, offset: Offset(0, 8)),
        BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)),
      ];
  static List<BoxShadow> get raised => const [
        BoxShadow(color: Color(0x262B6B48), blurRadius: 28, offset: Offset(0, 14)),
        BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2)),
      ];
}

class AppTheme {
  static const font = 'PlusJakartaSans';

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.ink,
      onSecondary: Colors.white,
      tertiary: AppColors.accent,
      error: AppColors.danger,
      surface: Colors.white,
      onSurface: AppColors.ink,
      surfaceTint: Colors.transparent,
      outline: AppColors.line,
      outlineVariant: AppColors.line,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: font);
    final text = base.textTheme
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink, fontFamily: font)
        .copyWith(
          headlineLarge: base.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1, color: AppColors.ink),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AppColors.ink),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5, color: AppColors.ink),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.ink),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
        );

    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    const buttonText = TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.surface,
      textTheme: text,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      }),
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: font, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.ink),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFCADBD0),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: buttonText,
          shape: pill,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          textStyle: buttonText,
          shape: pill,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          backgroundColor: Colors.white,
          minimumSize: const Size(64, 50),
          side: const BorderSide(color: AppColors.line),
          textStyle: buttonText.copyWith(fontWeight: FontWeight.w600),
          shape: pill,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: buttonText.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
          shape: pill,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: AppColors.ink)),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.danger)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: const Color(0x332B6B48),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.line)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.ink,
        titleTextStyle: TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink),
        subtitleTextStyle: TextStyle(fontFamily: font, fontSize: 13, color: AppColors.textMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.field,
        selectedColor: AppColors.primary,
        checkmarkColor: Colors.white,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(fontFamily: font, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink),
        secondaryLabelStyle: const TextStyle(fontFamily: font, fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: Colors.white,
          selectedBackgroundColor: AppColors.primary,
          selectedForegroundColor: Colors.white,
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.field),
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.mint,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontFamily: font,
              fontSize: 12,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? AppColors.ink : AppColors.textMuted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) =>
            IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primaryDark : AppColors.textMuted)),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.mint,
        selectedIconTheme: IconThemeData(color: AppColors.primaryDark),
        unselectedIconTheme: IconThemeData(color: AppColors.textMuted),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.ink,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.line,
        labelStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.w500, fontSize: 14),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        titleTextStyle: const TextStyle(fontFamily: font, fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.ink),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary, linearTrackColor: AppColors.field),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(fontFamily: font, color: Colors.white, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
