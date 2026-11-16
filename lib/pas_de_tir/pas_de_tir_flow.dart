import 'package:flutter/material.dart';

import 'ar_support.dart';
import 'pas_de_tir_result.dart';
import 'screens/ar_session_screen.dart';
import 'screens/classic_session_screen.dart';
import 'screens/gyro_session_screen.dart';
import 'screens/pas_de_tir_modals.dart';

/// Point d'entrée de la gamification, appelé au déclenchement géofence
/// (ou depuis l'historique pour rejouer).
///
/// Enchaînement : 02 intro → [08 caméra → 09–14 AR] ou [Gyroscope] ou [03–07 Classique].
/// Retourne null si l'utilisateur ferme avant le premier tir.
///
/// En mode démo, [demoMode] impose le mode (aucun autre n'est proposé) et la
/// modale caméra est sautée : la permission est demandée directement.
Future<PasDeTirResult?> runPasDeTir(BuildContext context, {bool replay = false, PasDeTirMode? demoMode}) async {
  // Rejeu depuis l'historique : toujours en Classique, sans capteurs.
  final (arAvailable, gyroAvailable) = replay || demoMode != null
      ? (false, false)
      : await (isArSupported(), isGyroSupported()).wait;
  if (!context.mounted) return null;

  final mode = await showPasDeTirIntro(
    context,
    arAvailable: arAvailable,
    gyroAvailable: gyroAvailable,
    onlyMode: replay ? null : demoMode,
  );
  if (mode == null || !context.mounted) return null;

  var useAr = mode == PasDeTirMode.ar;
  if (useAr) {
    final choice = demoMode != null ? CameraChoice.allow : await showCameraPermissionModal(context);
    if (choice == null || !context.mounted) return null;
    // Permission caméra refusée ou ARCore non installable : Classique, sans erreur.
    useAr = choice == CameraChoice.allow && await prepareAr();
    if (!context.mounted) return null;
  }

  final Widget? sensorScreen = useAr
      ? const ArSessionScreen()
      : mode == PasDeTirMode.gyro
      ? const GyroSessionScreen()
      : null;
  if (sensorScreen != null) {
    final r = await Navigator.push<Object?>(context, MaterialPageRoute(builder: (_) => sensorScreen));
    if (r is PasDeTirResult) return r;
    if (r is! ClassicFallbackSignal || !context.mounted) return null;
  }

  return Navigator.push<PasDeTirResult>(context, MaterialPageRoute(builder: (_) => const ClassicSessionScreen()));
}
