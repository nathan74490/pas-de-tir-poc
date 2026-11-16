import 'package:flutter/foundation.dart';

import '../pas_de_tir/pas_de_tir_result.dart';

/// Données factices de l'épreuve en cours (remplacées par le vrai modèle
/// de course et de gamifications dans l'app).
class RaceState extends ChangeNotifier {
  /// Gouttes déjà gagnées avant le pas de tir (dont Quiz : 40).
  static const baseDrops = 80;
  static const quizDrops = 40;
  static const dropGoal = 160;

  PasDeTirResult? pasDeTir;

  int get drops => baseDrops + (pasDeTir?.drops ?? 0);

  void recordPasDeTir(PasDeTirResult result) {
    pasDeTir = result;
    // Ici l'app enverrait result.toJson() au back (crédit des gouttes + classement).
    debugPrint('POST gamification/pas_de_tir ${result.toJson()}');
    notifyListeners();
  }
}
