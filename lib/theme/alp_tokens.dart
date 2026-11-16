import 'package:flutter/material.dart';

/// Tokens de design V2 Alpvengers (repris de la spec, à remplacer par ceux
/// de l'app lors de l'intégration).
abstract final class AlpColors {
  static const orange = Color(0xFFFF6B1A);
  static const petrol = Color(0xFF00607C);
  static const cyan = Color(0xFF00C8FF);
  static const alpcoin = Color(0xFFFFDD15);
  static const fir = Color(0xFF14532D);
  static const text = Color(0xFF0A0A0A);
  static const textSecondary = Color(0xFF737373);
  static const cream = Color(0xFFF5F3ED);
  static const modal = Color(0xFFFFEDD5);
  static const border = Color(0xFFE5E5E5);
  static const neutralButton = Color(0xFFEFEDE7);
}

abstract final class AlpRadii {
  static const card = 16.0;
  static const modal = 20.0;
  static const button = 12.0;
}

abstract final class AlpText {
  /// Titres en condensé majuscule (« PAS DE TIR », « MEILLEUR TIREUR DU JOUR »).
  static const condensed = TextStyle(
    fontFamily: 'sans-serif-condensed',
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );
}

ThemeData buildAlpTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AlpColors.orange, primary: AlpColors.orange),
    scaffoldBackgroundColor: AlpColors.cream,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AlpColors.text, displayColor: AlpColors.text),
  );
}
