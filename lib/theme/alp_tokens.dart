import 'package:flutter/material.dart';

/// Tokens de design V2 Alpvengers (repris de la maquette Figma, à remplacer
/// par ceux de l'app lors de l'intégration).
abstract final class AlpColors {
  static const orange = Color(0xFFFF6B1A);
  static const petrol = Color(0xFF00607C);
  static const cyan = Color(0xFF00C8FF);

  /// « goutte-clair » : remplissage des barres de progression.
  static const dropLight = Color(0xFF38BDF8);
  static const alpcoin = Color(0xFFFFDD15);
  static const fir = Color(0xFF14532D);
  static const text = Color(0xFF0A0A0A);

  /// Titres des modales crème.
  static const ink = Color(0xFF1E1E1E);

  /// Sous-titres des modales crème.
  static const slate = Color(0xFF303D4D);
  static const textSecondary = Color(0xFF737373);
  static const cream = Color(0xFFF5F3ED);
  static const modal = Color(0xFFFFEDD5);
  static const border = Color(0xFFE5E5E5);
  static const neutralButton = Color(0xFFEFEDE7);

  /// Fond des toasts sombres et de la barre de stats sur décor.
  static const darkToast = Color(0xE62F2F2F);
  static const darkBar = Color(0x802F2F2F);
}

abstract final class AlpRadii {
  static const card = 16.0;
  static const modal = 16.0;
  static const button = 12.0;
}

abstract final class AlpText {
  static const fontFamily = 'Figtree';

  /// Titres en condensé majuscule (« MEILLEUR TIREUR DU JOUR »).
  static const condensed = TextStyle(
    fontFamily: 'sans-serif-condensed',
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );
}

ThemeData buildAlpTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: AlpText.fontFamily,
    colorScheme: ColorScheme.fromSeed(seedColor: AlpColors.orange, primary: AlpColors.orange),
    scaffoldBackgroundColor: AlpColors.cream,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AlpColors.text, displayColor: AlpColors.text),
  );
}
